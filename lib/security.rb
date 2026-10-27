# frozen_string_literal: true

require 'ipaddr'
require 'uri'

module FatAngel
  module Clock
    def self.now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end

  # A bounded, monotonic token bucket. It does not retain message history.
  class TokenBucket
    def initialize(capacity:, refill_per_second:, now: Clock.now)
      @capacity = Float(capacity)
      @refill_per_second = Float(refill_per_second)
      @updated_at = Float(now)
      unless @capacity.finite? && @capacity.positive? &&
             @refill_per_second.finite? && @refill_per_second >= 0 && @updated_at.finite?
        raise ArgumentError, 'Invalid token bucket configuration'
      end

      @tokens = @capacity
    end

    def allow?(cost = 1, now: Clock.now)
      cost = Float(cost)
      now = Float(now)
      return false unless cost.finite? && cost.positive? && cost <= @capacity && now.finite?

      elapsed = [now - @updated_at, 0].max
      @tokens = [@capacity, @tokens + elapsed * @refill_per_second].min
      @updated_at = [now, @updated_at].max
      return false if @tokens < cost

      @tokens -= cost
      true
    rescue ArgumentError, TypeError
      false
    end
  end

  module TextPolicy
    MAX_BYTES = 4096
    # Keep ordinary Unicode, including emoji ZWJ sequences, while rejecting
    # controls, line breaks and direction/invisible characters used for spoofing.
    FORBIDDEN = /[\u0000-\u001f\u007f-\u009f\u061c\u200b\u200e\u200f\u2028-\u202e\u2060\u2066-\u2069\ufeff]/

    def self.normalize(value, min:, max:)
      return nil unless value.is_a?(String) && value.bytesize <= MAX_BYTES
      return nil unless [Encoding::UTF_8, Encoding::US_ASCII].include?(value.encoding)
      return nil unless value.valid_encoding?

      text = value.encode(Encoding::UTF_8)
      return nil if FORBIDDEN.match?(text)

      text = text.unicode_normalize(:nfc).gsub(/\A[[:space:]]+|[[:space:]]+\z/, '')
      return nil unless text.bytesize <= MAX_BYTES && (min..max).cover?(text.length)

      text
    rescue ArgumentError, EncodingError
      nil
    end
  end

  module RequestPolicy
    MAX_HEADER_BYTES = 4096
    MAX_FORWARDED_IPS = 20

    def self.expected_origin(env)
      scheme = env.fetch('rack.url_scheme', 'http').to_s.downcase
      if ENV['RENDER'] == 'true' || trusted_proxy?(canonical_ip(env['REMOTE_ADDR']))
        forwarded_scheme = env['HTTP_X_FORWARDED_PROTO']
        if forwarded_scheme.is_a?(String) && forwarded_scheme.bytesize <= 5 && forwarded_scheme.ascii_only?
          forwarded_scheme = forwarded_scheme.downcase
          scheme = forwarded_scheme if %w[http https].include?(forwarded_scheme)
        end
      end
      return nil unless %w[http https].include?(scheme)

      host = env['HTTP_HOST']
      return nil unless host.is_a?(String) && host.bytesize <= 512 && host.ascii_only?

      parse_origin("#{scheme}://#{host}")
    end

    def self.origin_allowed?(env)
      supplied = env['HTTP_ORIGIN']
      # Native clients may omit Origin; this anonymous game uses no cookie auth.
      return true if supplied.nil?

      actual = parse_origin(supplied)
      expected = expected_origin(env)
      actual && expected && actual.scheme == expected.scheme &&
        actual.hostname.downcase == expected.hostname.downcase && actual.port == expected.port || false
    end

    def self.client_ip(env)
      peer = canonical_ip(env['REMOTE_ADDR'])
      return peer || 'unknown' unless peer && trusted_proxy?(peer)

      header = env['HTTP_X_FORWARDED_FOR']
      return peer unless header.is_a?(String) && header.bytesize <= MAX_HEADER_BYTES && header.ascii_only?

      values = header.split(',', -1)
      return peer if values.empty? || values.length > MAX_FORWARDED_IPS

      addresses = values.map { |address| canonical_ip(address.strip) }
      return peer if addresses.any?(&:nil?)

      candidate = peer
      addresses.reverse_each do |address|
        break unless trusted_proxy?(candidate)

        candidate = address
      end
      candidate
    end

    def self.http_headers(env)
      origin = expected_origin(env)
      websocket_origin = origin&.to_s&.sub(/\Ahttp/, 'ws')
      connect_sources = ["'self'", websocket_origin].compact.join(' ')
      {
        'content-security-policy' => [
          "default-src 'self'", "script-src 'self'", "style-src 'self'",
          "img-src 'self' data:", "connect-src #{connect_sources}",
          "object-src 'none'", "base-uri 'none'", "form-action 'self'", "frame-ancestors 'none'"
        ].join('; '),
        'x-content-type-options' => 'nosniff',
        'x-frame-options' => 'DENY',
        'referrer-policy' => 'no-referrer'
      }
    end

    def self.parse_origin(value)
      return nil unless value.is_a?(String) && value.bytesize <= 512 && value.ascii_only?

      # URI#normalize inserts '/', but a browser Origin has no path.
      uri = URI.parse(value)
      return nil unless uri.is_a?(URI::HTTP) && %w[http https].include?(uri.scheme)
      return nil unless uri.userinfo.nil? && uri.path.to_s.empty? && uri.query.nil? && uri.fragment.nil?
      return nil unless uri.hostname && (1..65_535).cover?(uri.port)

      # URI permits semicolons and other sub-delimiters in reg-names. Those
      # must never reach the CSP connect-src directive through a Host header.
      hostname = uri.hostname
      if hostname.include?(':')
        return nil unless canonical_ip(hostname)
      else
        return nil unless hostname.bytesize <= 253 && /\A[a-z0-9._-]+\z/i.match?(hostname)
      end
      uri
    rescue URI::Error, ArgumentError, EncodingError
      nil
    end
    private_class_method :parse_origin

    def self.canonical_ip(value)
      return nil unless value.is_a?(String) && value.bytesize <= 64 && value.ascii_only?
      return nil if value.empty? || /[\s\/%\[\]]/.match?(value)

      IPAddr.new(value).native.to_s
    rescue IPAddr::Error, ArgumentError
      nil
    end
    private_class_method :canonical_ip

    def self.trusted_proxy?(address)
      return false unless address

      ip = IPAddr.new(address)
      trusted_networks.any? { |network| network.include?(ip) }
    rescue IPAddr::Error, ArgumentError
      false
    end
    private_class_method :trusted_proxy?

    def self.trusted_networks
      configured = ENV.fetch('TRUSTED_PROXY_CIDRS', '')
      if @trusted_proxy_config != configured
        @trusted_networks = configured.split(',').filter_map do |entry|
          next if entry.strip.empty?

          IPAddr.new(entry.strip)
        rescue IPAddr::Error, ArgumentError
          nil
        end.freeze
        @trusted_proxy_config = configured.dup.freeze
      end
      @trusted_networks
    end
    private_class_method :trusted_networks
  end
end
