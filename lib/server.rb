require 'json'
require 'faye/websocket'
require 'sinatra/base'
require 'thin'
require_relative 'game'
require_relative 'security'

Faye::WebSocket.load_adapter('thin')

module FatAngel
  class Session
    attr_accessor :player, :subscribed
    attr_reader :id, :ip, :socket, :created_at, :last_pong

    def initialize(id, ip, socket, connection)
      @id, @ip, @socket, @connection = id, ip, socket, connection
      @created_at = @last_pong = @last_ping = Clock.now
      @player, @subscribed, @closing = nil, false, false
      @messages = TokenBucket.new(capacity: 160, refill_per_second: 120)
      @chat = TokenBucket.new(capacity: 5, refill_per_second: 0.5)
      @states = TokenBucket.new(capacity: 2, refill_per_second: 30)
      @names = TokenBucket.new(capacity: 5, refill_per_second: 0.5)
      @shots = TokenBucket.new(capacity: 4, refill_per_second: 4)
      @resets = TokenBucket.new(capacity: 2, refill_per_second: 0.5)
      @limits = {message: @messages, chat: @chat, state: @states, name: @names,
                 shot: @shots, reset: @resets}.freeze
      @errors = TokenBucket.new(capacity: 10, refill_per_second: 10)
      @last_rate_error = -Float::INFINITY
    end

    def joined?
      @player && !@closing
    end

    def closing?
      @closing
    end

    def allow?(type)
      @limits.fetch(type).allow?
    end

    def send_packet(packet)
      return if @closing || @socket.ready_state != Faye::WebSocket::OPEN
      # Faye's buffered_amount is always zero for this Thin adapter. Inspect the real socket.
      if @connection&.respond_to?(:get_outbound_data_size) && @connection.get_outbound_data_size > 262_144
        close(4009, 'Slow consumer')
        return
      end
      @socket.send(packet)
    end

    def error(code, message)
      return unless @errors.allow?
      if code == 'rate_limited'
        return if Clock.now - @last_rate_error < 1.0
        @last_rate_error = Clock.now
      end
      send_packet("e:#{JSON.generate(code: code, message: message)}")
    end

    def close(code, reason)
      return if @closing
      @closing = true
      @socket.close(code, reason)
      # Do not retain unresponsive peers for Faye's full 30-second close timeout.
      EventMachine.add_timer(1) do
        @connection.close_connection if @connection && @socket.ready_state != Faye::WebSocket::CLOSED
      end
    end

    def heartbeat(now)
      return if @closing
      return close(4000, 'Heartbeat timeout') if now - @last_pong > 60
      return unless now - @last_ping >= 25
      @last_ping = now
      @socket.ping('alive') { @last_pong = Clock.now }
    end
  end

  class Room
    MAX_CONNECTIONS = 25
    MAX_PER_IP = 8
    MAX_IP_BUCKETS = 2048
    attr_reader :world, :sessions

    def initialize(world: World.new)
      @world, @sessions, @ip_buckets = world, [], {}
      @next_id, @timer = 0, nil
    end

    def reserve(ip)
      now = Clock.now
      @ip_buckets.delete_if { |_key, value| now - value[:seen] > 120 && !@sessions.any? { |s| s.ip == _key } }
      return [503, 'Server busy'] if @sessions.size >= MAX_CONNECTIONS
      return [429, 'Too many connections'] if @sessions.count { |s| s.ip == ip } >= MAX_PER_IP
      return [503, 'Server busy'] if !@ip_buckets.key?(ip) && @ip_buckets.size >= MAX_IP_BUCKETS
      bucket = (@ip_buckets[ip] ||= {seen: now,
        connect: TokenBucket.new(capacity: 5, refill_per_second: 1),
        chat: TokenBucket.new(capacity: 10, refill_per_second: 1)})
      bucket[:seen] = now
      return [429, 'Connection rate limit'] unless bucket[:connect].allow?
      nil
    end

    def attach(ip, socket, connection)
      @next_id += 1
      session = Session.new(@next_id, ip, socket, connection)
      @sessions << session
      start!
      session
    end

    def remove(session)
      @world.leave(session.player) if session.player
      @sessions.delete(session)
    end

    def start!
      return if @timer
      @last_time = @last_sweep = Clock.now
      @next_broadcast = @last_time + 1.0 / SNAPSHOT_RATE
      @accumulator = 0.0
      @timer = EventMachine.add_periodic_timer(1.0 / TICK_RATE) { advance }
    end

    def advance
      now = Clock.now
      @accumulator += [now - @last_time, 0.25].min
      @last_time = now
      steps = [(@accumulator * TICK_RATE).floor, 5].min
      steps.times do
        @world.step do |collector|
          @sessions.find { |session| session.player.equal?(collector) }&.send_packet('b:Ciężka miłość')
        end
        @accumulator -= 1.0 / TICK_RATE
      end
      @accumulator %= 1.0 / TICK_RATE if steps == 5
      if now + 1e-9 >= @next_broadcast
        @next_broadcast += 1.0 / SNAPSHOT_RATE
        @next_broadcast = now + 1.0 / SNAPSHOT_RATE if @next_broadcast <= now
        unless @world.players.empty?
          packet = @world.snapshot_packet(refresh: true)
          @sessions.each { |session| session.send_packet(packet) if session.joined? && session.subscribed }
        end
      end
      return if now - @last_sweep < 1
      @last_sweep = now
      @sessions.each do |session|
        if !session.player && now - session.created_at > 30
          session.close(4000, 'Join timeout')
        else
          session.heartbeat(now)
        end
      end
    end

    def receive(session, message)
      return if session.closing?
      unless message.is_a?(String) && message.encoding != Encoding::BINARY && message.valid_encoding?
        session.close(4003, 'Text frames required')
        return
      end
      unless session.allow?(:message)
        session.close(4009, 'Message rate limit')
        return
      end
      case message
      when 'i'
        session.send_packet("i:#{session.id}")
      when /\An/
        join(session, message[1..])
      else
        unless session.joined?
          session.error('not_joined', 'Najpierw wybierz poprawny nick.')
          return
        end
        receive_joined(session, message)
      end
    end

    private

    def join(session, input)
      unless session.allow?(:name)
        session.error('rate_limited', 'Zbyt wiele prób. Poczekaj chwilę.')
        return
      end
      name = TextPolicy.normalize(input, min: 2, max: 30)
      unless name
        session.error('invalid_name', 'Nick musi mieć 2–30 znaków i nie może zawierać znaków sterujących.')
        return
      end
      if session.player
        if session.player.name != name
          session.error('name_locked', 'Nick jest przypisany do tej sesji. Aby go zmienić, połącz się ponownie.')
          return
        end
      elsif @world.players.any? { |player| player.name.downcase == name.downcase }
        session.error('name_taken', 'Ten nick jest już zajęty.')
        return
      else
        session.player = @world.join(session.id, name)
      end
      session.send_packet("a:#{JSON.generate(id: session.id, name: name)}")
    end

    def receive_joined(session, message)
      player = session.player
      case message
      when 's'
        session.subscribed = true
      when 'j'
        session.send_packet(@world.snapshot_packet) if session.allow?(:state)
      when 'l', 'r', 't', 'b'
        player.control(message)
      when 'q'
        player.reset(@world_random ||= Random.new) if session.allow?(:reset)
      when /\Ap/
        return unless session.allow?(:shot)
        coordinates = message[1..].split(',', -1)
        return unless coordinates.size == 2
        coordinates.map! { |value| Float(value, exception: false) }
        return unless coordinates.all? { |value| value && value.finite? && value.abs <= 10_000_000 }
        player.bullet = Bullet.new(player, coordinates)
      when /\Am/
        chat(session, message[1..])
      else
        session.error('invalid_command', 'Nieprawidłowe polecenie.')
      end
    end

    def chat(session, input)
      ip_limit = @ip_buckets.fetch(session.ip)
      ip_limit[:seen] = Clock.now
      socket_allowed = session.allow?(:chat)
      ip_allowed = ip_limit[:chat].allow?
      unless socket_allowed && ip_allowed
        session.error('rate_limited', 'Zbyt wiele wiadomości. Poczekaj chwilę przed wysłaniem następnej.')
        return
      end
      text = TextPolicy.normalize(input, min: 1, max: 500)
      unless text
        session.error('invalid_chat', 'Wiadomość musi mieć 1–500 znaków, bez znaków sterujących i ukrytych kierunków tekstu.')
        return
      end
      packet = "c:#{JSON.generate(id: session.id, name: session.player.name, text: text)}"
      @sessions.each { |recipient| recipient.send_packet(packet) if recipient.joined? }
    end
  end

  ROOM = Room.new

  class App < Sinatra::Base
    set :environment, ENV.fetch('RACK_ENV', 'production').to_sym
    set :root, File.expand_path('..', __dir__)

    get('/') { erb :index }
    get '/healthz' do
      content_type :json
      {status: 'ok', version: VERSION, players: ROOM.world.players.size}.to_json
    end
  end

  class WebSocketApp
    def initialize(room: ROOM)
      @room = room
    end

    def call(env)
      unless env['PATH_INFO'] == '/ws'
        status, headers, body = App.call(env)
        return [status, headers.merge(RequestPolicy.http_headers(env)), body]
      end
      return response(env, 400, 'Invalid host') unless RequestPolicy.expected_origin(env)
      return response(env, 403, 'Origin rejected') unless RequestPolicy.origin_allowed?(env)
      return response(env, 426, 'WebSocket required', 'upgrade' => 'websocket') unless Faye::WebSocket.websocket?(env)
      ip = RequestPolicy.client_ip(env)
      failure = @room.reserve(ip)
      return response(env, *failure) if failure
      socket = Faye::WebSocket.new(env, nil, max_length: 4096)
      session = @room.attach(ip, socket, env['em.connection'])
      socket.on(:message) { |event| @room.receive(session, event.data) }
      socket.on(:close) { |_event| @room.remove(session) }
      socket.rack_response
    end

    private

    def response(env, code, text, headers = {})
      [code, RequestPolicy.http_headers(env).merge('content-type' => 'text/plain; charset=utf-8').merge(headers), [text]]
    end
  end
end
