# frozen_string_literal: true

# Pure in-process tests: no listening socket or running server required.
require_relative '../server'
require 'rack/mock'

module Checks
  @count = @assertions = @failures = 0
  class << self
    def test(name)
      @count += 1
      yield
      puts "PASS #{name}"
    rescue StandardError => error
      @failures += 1
      warn "FAIL #{name}: #{error.message}\n  #{error.backtrace.first(3).join("\n  ")}"
    end

    def assert(value, message = 'Assertion failed')
      @assertions += 1
      raise message unless value
    end

    def equal(expected, actual)
      assert(expected == actual, "Expected #{expected.inspect}, got #{actual.inspect}")
    end

    def finish
      puts "#{@count} tests, #{@assertions} assertions, #{@failures} failures"
      exit(@failures.zero? ? 0 : 1)
    end

    def env(values)
      original = values.to_h { |key, _value| [key, ENV[key]] }
      values.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
      yield
    ensure
      original.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    end
  end
end

class FakeSocket
  attr_reader :sent, :closed, :pings
  attr_accessor :ready_state
  def initialize
    @sent, @pings = [], 0
    @ready_state = Faye::WebSocket::OPEN
  end
  def send(packet) = @sent << packet
  def close(code, reason)
    @closed = [code, reason]
    @ready_state = Faye::WebSocket::CLOSED
  end
  def ping(_message)
    @pings += 1
    yield if block_given?
  end
  def last(type)
    packet = @sent.reverse.find { |item| item.start_with?("#{type}:") }
    packet && JSON.parse(packet[2..])
  end
end

FakeConnection = Struct.new(:get_outbound_data_size) do
  def close_connection; end
end

def session_in(room, ip = '192.0.2.1', name = nil)
  Checks.equal(nil, room.reserve(ip))
  socket = FakeSocket.new
  session = room.attach(ip, socket, FakeConnection.new(0))
  room.receive(session, "n#{name}") if name
  [session, socket]
end

Checks.test('token bucket bounds bursts, refills and ignores backward clock jumps') do
  bucket = FatAngel::TokenBucket.new(capacity: 2, refill_per_second: 0.5, now: 10)
  Checks.assert(bucket.allow?(now: 10))
  Checks.assert(bucket.allow?(now: 10))
  Checks.assert(!bucket.allow?(now: 10))
  Checks.assert(!bucket.allow?(now: 9))
  Checks.assert(!bucket.allow?(now: 11.9))
  Checks.assert(bucket.allow?(now: 12))
  Checks.assert(!bucket.allow?(Float::NAN, now: 12))
  Checks.assert(!bucket.allow?(now: Float::INFINITY))
  Checks.assert(bucket.allow?(2, now: 100))
  Checks.assert(!bucket.allow?(now: 100))
end

Checks.test('Unicode validation preserves Polish and emoji, normalizes NFC and enforces code points') do
  policy = FatAngel::TextPolicy
  Checks.equal('éx', policy.normalize("  e\u0301x  ", min: 2, max: 30))
  Checks.equal('Zażółć 👩‍💻', policy.normalize('Zażółć 👩‍💻', min: 1, max: 500))
  Checks.equal('😀' * 500, policy.normalize('😀' * 500, min: 1, max: 500))
  Checks.equal(nil, policy.normalize('😀' * 501, min: 1, max: 500))
  Checks.equal(nil, policy.normalize('x', min: 2, max: 30))
  Checks.equal(nil, policy.normalize(' ' * 10, min: 1, max: 500))
  Checks.equal(nil, policy.normalize("\xc3\x28".dup.force_encoding('UTF-8'), min: 1, max: 500))
  Checks.equal(nil, policy.normalize('binary'.b, min: 1, max: 500))
  [0, 10, 13, 0x85, 0x61c, 0x200b, 0x200e, 0x2028, 0x202e, 0x2060, 0x2066, 0xfeff].each do |code|
    Checks.equal(nil, policy.normalize("ab#{code.chr('UTF-8')}", min: 1, max: 500))
  end
end

Checks.env('TRUSTED_PROXY_CIDRS' => nil, 'RENDER' => nil) do
  Checks.test('Origin compares the full scheme/host/port and rejects malformed or injected hosts') do
    policy = FatAngel::RequestPolicy
    base = {'rack.url_scheme' => 'https', 'HTTP_HOST' => 'example.com', 'REMOTE_ADDR' => '192.0.2.1'}
    Checks.equal('https://example.com', policy.expected_origin(base).to_s)
    Checks.assert(policy.origin_allowed?(base)) # Anonymous native clients may omit Origin.
    ['https://example.com', 'https://EXAMPLE.com:443'].each do |origin|
      Checks.assert(policy.origin_allowed?(base.merge('HTTP_ORIGIN' => origin)))
    end
    ['null', '', 'http://example.com', 'https://example.com:444', 'https://evil.test',
     'https://example.com/', 'https://user@example.com', 'https://example.com?q=1',
     "https://example.com\r\nX: bad"].each do |origin|
      Checks.assert(!policy.origin_allowed?(base.merge('HTTP_ORIGIN' => origin)), origin)
    end
    ['evil.test;script-src', 'example.com/path', "example.com\r\n", 'example.com:99999'].each do |host|
      Checks.equal(nil, policy.expected_origin(base.merge('HTTP_HOST' => host)))
    end
    headers = policy.http_headers(base)
    Checks.assert(headers['content-security-policy'].include?('connect-src \'self\' wss://example.com'))
    Checks.assert(!headers['content-security-policy'].include?('unsafe-'))
    Checks.equal('nosniff', headers['x-content-type-options'])
  end

  Checks.test('untrusted forwarded headers cannot change client IP or origin scheme') do
    env = {'rack.url_scheme' => 'http', 'HTTP_HOST' => 'localhost:8080', 'REMOTE_ADDR' => '192.0.2.1',
           'HTTP_X_FORWARDED_FOR' => '198.51.100.1', 'HTTP_X_FORWARDED_PROTO' => 'https'}
    Checks.equal('192.0.2.1', FatAngel::RequestPolicy.client_ip(env))
    Checks.equal('http://localhost:8080', FatAngel::RequestPolicy.expected_origin(env).to_s)
    Checks.env('TRUSTED_PROXY_CIDRS' => '10.0.0.0/8, 192.0.2.0/24') do
      forwarded = env.merge('HTTP_X_FORWARDED_FOR' => '203.0.113.99, 198.51.100.1, 10.0.0.2')
      Checks.equal('198.51.100.1', FatAngel::RequestPolicy.client_ip(forwarded))
      Checks.equal('https://localhost:8080', FatAngel::RequestPolicy.expected_origin(forwarded).to_s)
      Checks.equal('192.0.2.1', FatAngel::RequestPolicy.client_ip(forwarded.merge('HTTP_X_FORWARDED_FOR' => 'bad')))
    end
    Checks.env('RENDER' => 'true') do
      Checks.equal('https://localhost:8080', FatAngel::RequestPolicy.expected_origin(env).to_s)
      Checks.equal('192.0.2.1', FatAngel::RequestPolicy.client_ip(env))
    end
  end
end

Checks.test('snapshot reads share one encoding and do not advance physics') do
  world = FatAngel::World.new(random: Random.new(1))
  world.join(1, 'Ala')
  packet = world.snapshot_packet
  1000.times { Checks.assert(packet.equal?(world.snapshot_packet)) }
  Checks.equal(0, world.tick)
  Checks.equal(1, world.snapshot_encodes)
  60.times { world.step }
  Checks.equal(60, world.tick)
  Checks.assert(packet.equal?(world.snapshot_packet))
  Checks.equal(60, JSON.parse(world.snapshot_packet(refresh: true)[2..])['tick'])
  world.leave(world.players.first)
  Checks.equal([], JSON.parse(world.snapshot_packet[2..])['id'])
end

Checks.test('movement is bounded, animation stays in sprite range and respawns are explicit') do
  random = Random.new(2)
  player = FatAngel::Player.new(1, 'Ala', random)
  player.x = player.y = 0
  100.times { player.control('r') }
  player.step(random)
  Checks.equal(20.0, player.x)
  100.times { player.control('l') }
  player.step(random)
  Checks.equal(0.0, player.x)
  1000.times do
    player.step(random)
    Checks.assert((0..49).cover?(player.frame))
  end
  player.score, player.size = 5, 140
  player.reset(random)
  Checks.equal(1, player.respawns)
  Checks.equal(5, player.score)
  Checks.equal(140, player.size)
  before = player.x
  player.step(random)
  Checks.equal(before, player.x)
end

Checks.test('one bullet hits one victim, increments owner score and caps growth') do
  world = FatAngel::World.new(random: Random.new(3))
  owner, victim, other = [world.join(1, 'Ala'), world.join(2, 'Ola'), world.join(3, 'Ela')]
  owner.x = owner.y = victim.y = other.y = 0
  victim.x = other.x = 30
  victim.size = 150
  world.bonuses.each { |bonus| bonus[0] = bonus[1] = -100_000 }
  owner.bullet = FatAngel::Bullet.new(owner, [100, 0])
  world.step
  Checks.equal(1, owner.score)
  Checks.equal(nil, owner.bullet)
  Checks.equal(150, victim.size)
  Checks.equal(1, victim.respawns)
  Checks.equal(0, other.respawns)
end

Checks.test('zero-length shots remain finite and unused bullets expire after five seconds') do
  random = Random.new(4)
  player = FatAngel::Player.new(1, 'Ala', random)
  bullet = FatAngel::Bullet.new(player, [player.x, player.y])
  299.times { bullet.step }
  Checks.assert(!bullet.expired?)
  bullet.step
  Checks.assert(bullet.expired?)
  Checks.assert(bullet.x.finite? && bullet.y.finite?)
end

Checks.test('WebSocket driver enforces byte limits, UTF-8 and fragmented message limits in memory') do
  wire_class = Struct.new(:env, :url, :written) do
    def write(data) = written << data
  end
  frame = lambda do |payload, opcode = 1, final = true|
    mask = [1, 2, 3, 4]
    size = payload.bytesize
    header = [opcode | (final ? 0x80 : 0), size < 126 ? (0x80 | size) : 0xfe].pack('C*')
    header += [size].pack('n') if size >= 126
    header + mask.pack('C*') + payload.bytes.each_with_index.map { |byte, i| byte ^ mask[i % 4] }.pack('C*')
  end
  [[['x' * 4096], nil], [['x' * 4097], 1009], [["\xc3\x28".b], 1007],
   [['x' * 3000, 'x' * 2000], 1009]].each do |payloads, expected_close|
    env = {'REQUEST_METHOD' => 'GET', 'HTTP_CONNECTION' => 'Upgrade', 'HTTP_UPGRADE' => 'websocket',
           'HTTP_SEC_WEBSOCKET_VERSION' => '13', 'HTTP_SEC_WEBSOCKET_KEY' => 'dGhlIHNhbXBsZSBub25jZQ=='}
    driver = WebSocket::Driver.rack(wire_class.new(env, 'ws://localhost/ws', []), max_length: 4096)
    messages, closed = [], nil
    driver.on(:message) { |event| messages << event.data }
    driver.on(:close) { |event| closed = event.code }
    driver.on(:error) { |_error| nil }
    Checks.assert(driver.start)
    payloads.each_with_index do |payload, index|
      driver.parse(frame.call(payload, index.zero? ? 1 : 0, index == payloads.size - 1))
    end
    Checks.equal(expected_close, closed)
    Checks.equal(expected_close ? [] : payloads, messages)
  end
end

# Replace timers and the monotonic clock only inside these in-memory tests.
# No event loop, HTTP listener, or WebSocket connection is created.
original_clock = FatAngel::Clock.method(:now)
original_periodic = EventMachine.method(:add_periodic_timer)
original_timer = EventMachine.method(:add_timer)
now = 0.0
FatAngel::Clock.define_singleton_method(:now) { now }
EventMachine.define_singleton_method(:add_periodic_timer) { |_interval, &_block| Object.new }
EventMachine.define_singleton_method(:add_timer) { |_interval, &_block| Object.new }
begin
  Checks.test('room requires accepted identity, locks nick and rejects duplicate names') do
    room = FatAngel::Room.new
    session, socket = session_in(room)
    %w[mhello r s j].each do |message|
      room.receive(session, message)
      Checks.equal('not_joined', socket.last('e')['code'])
    end
    Checks.equal(0, room.world.players.size)
    room.receive(session, "n e\u0301x ")
    Checks.equal({'id' => session.id, 'name' => 'éx'}, socket.last('a'))
    room.receive(session, 'nChanged')
    Checks.equal('name_locked', socket.last('e')['code'])
    other, other_socket = session_in(room, '192.0.2.2')
    room.receive(other, 'nÉX')
    Checks.equal('name_taken', other_socket.last('e')['code'])
  end

  Checks.test('chat binds sender to session, preserves HTML as data and limits bursts per socket and IP') do
    room = FatAngel::Room.new
    first, sender = session_in(room, '192.0.2.1', 'Ala')
    second, _sender2 = session_in(room, '192.0.2.1', 'Ola')
    third, recipient = session_in(room, '192.0.2.1', 'Ela')
    html = '<img src=x onerror="alert(1)">'
    room.receive(first, "m#{html}")
    Checks.equal({'id' => first.id, 'name' => 'Ala', 'text' => html}, recipient.last('c'))
    4.times { room.receive(first, 'mhello') }
    count = recipient.sent.size
    room.receive(first, 'mblocked')
    Checks.equal('rate_limited', sender.last('e')['code'])
    Checks.equal(count, recipient.sent.size)
    # The blocked attempt also consumes the shared IP budget.
    4.times { room.receive(second, 'mhello') }
    count = recipient.sent.size
    room.receive(third, 'mblocked-by-IP')
    Checks.equal(count + 1, recipient.sent.size) # Only the error to this sender.
    Checks.equal('rate_limited', recipient.last('e')['code'])
    now += 10
    room.receive(first, "m e\u0301 ")
    Checks.equal('é', recipient.last('c')['text'])
  end

  Checks.test('invalid chat consumes budget and never broadcasts; binary and message floods close') do
    room = FatAngel::Room.new
    session, socket = session_in(room, '192.0.2.1', 'Ala')
    ['', ' ', "x\0", "x\u202e", 'x' * 501].each do |text|
      room.receive(session, "m#{text}")
      Checks.equal('invalid_chat', socket.last('e')['code'])
    end
    room.receive(session, 'mhello')
    Checks.equal('rate_limited', socket.last('e')['code'])
    Checks.equal(nil, socket.last('c'))
    other, binary = session_in(room, '192.0.2.2')
    room.receive(other, 'binary'.b)
    Checks.equal(4003, binary.closed.first)
    flood, flood_socket = session_in(room, '192.0.2.3')
    161.times { room.receive(flood, 'i') }
    Checks.equal(4009, flood_socket.closed.first)
  end

  Checks.test('fixed clock advances without polling, caps catch-up work and shares push snapshots') do
    room = FatAngel::Room.new
    first, socket = session_in(room, '192.0.2.1', 'Ala')
    second, other = session_in(room, '192.0.2.2', 'Ola')
    room.receive(first, 's')
    room.receive(second, 's')
    room.receive(first, 'r')
    start_x = first.player.x
    60.times do
      now += 1.0 / 60
      room.advance
    end
    Checks.assert((59..60).cover?(room.world.tick))
    Checks.assert(first.player.x > start_x)
    pushes = socket.sent.grep(/\Aj:/)
    Checks.equal(20, pushes.size)
    Checks.equal(pushes, other.sent.grep(/\Aj:/))
    Checks.equal(pushes.size, room.world.snapshot_encodes)
    tick = room.world.tick
    20.times { room.receive(first, 'j') }
    Checks.equal(tick, room.world.tick)
    now += 60
    room.advance
    Checks.assert(room.world.tick <= tick + 5)
  end

  Checks.test('connection, idle-join, heartbeat and slow-consumer limits are enforced') do
    room = FatAngel::Room.new
    5.times { Checks.equal(nil, room.reserve('192.0.2.1')) }
    Checks.equal(429, room.reserve('192.0.2.1').first)
    now += 5
    8.times do
      session_in(room, '192.0.2.1')
      now += 1
    end
    Checks.equal(429, room.reserve('192.0.2.1').first)
    17.times { |index| session_in(room, "198.51.100.#{index}") }
    Checks.equal(503, room.reserve('203.0.113.1').first)
    now += 31
    room.advance
    Checks.assert(room.sessions.all?(&:closing?))
    session = FatAngel::Session.new(100, '192.0.2.1', FakeSocket.new, FakeConnection.new(300_000))
    session.send_packet('hello')
    Checks.equal(4009, session.socket.closed.first)
    heart = FatAngel::Session.new(101, '192.0.2.1', FakeSocket.new, nil)
    heart.heartbeat(now + 61)
    Checks.equal(4000, heart.socket.closed.first)
  end

  Checks.test('per-IP bookkeeping is bounded and stale entries are reclaimed') do
    room = FatAngel::Room.new
    FatAngel::Room::MAX_IP_BUCKETS.times { |index| Checks.equal(nil, room.reserve("ip-#{index}")) }
    Checks.equal(503, room.reserve('new-address').first)
    now += 121
    Checks.equal(nil, room.reserve('new-address'))
  end

  Checks.test('shot and reset budgets reject bursts and malformed targets never create bullets') do
    room = FatAngel::Room.new
    session, socket = session_in(room, '192.0.2.1', 'Ala')
    ['pNaN,0', 'pInfinity,0', 'p0,0,0', 'p10000001,0'].each { |message| room.receive(session, message) }
    Checks.equal(nil, session.player.bullet)
    now += 1
    4.times { room.receive(session, 'p100,0') }
    bullet = session.player.bullet
    Checks.assert(bullet)
    room.receive(session, 'p200,0')
    Checks.assert(bullet.equal?(session.player.bullet))
    3.times { room.receive(session, 'q') }
    Checks.equal(2, session.player.respawns)
    now += 2
    room.receive(session, 'q')
    Checks.equal(3, session.player.respawns)
    Checks.equal(nil, socket.closed)
  end
ensure
  FatAngel::Clock.define_singleton_method(:now, original_clock)
  EventMachine.define_singleton_method(:add_periodic_timer, original_periodic)
  EventMachine.define_singleton_method(:add_timer, original_timer)
end

Checks.test('Rack serves the new UI and security headers without a listening socket') do
  request = Rack::MockRequest.new(FatAngel::WebSocketApp.new)
  response = request.get('/', 'HTTP_HOST' => 'localhost:8080')
  Checks.equal(200, response.status)
  Checks.assert(response.body.include?('id="join-form"') && response.body.include?('id="chat-history"'))
  Checks.assert(!response.body.include?('canvasquery') && !response.body.include?('jquery'))
  Checks.equal('DENY', response['x-frame-options'])
  Checks.assert(response['content-security-policy'].include?("script-src 'self'"))
  health = request.get('/healthz', 'HTTP_HOST' => 'localhost:8080')
  Checks.equal('0.0.2', JSON.parse(health.body)['version'])
  Checks.equal(426, request.get('/ws', 'HTTP_HOST' => 'localhost:8080').status)
  Checks.equal(403, request.get('/ws', 'HTTP_HOST' => 'localhost:8080', 'HTTP_ORIGIN' => 'https://evil.test').status)
end

Checks.finish
