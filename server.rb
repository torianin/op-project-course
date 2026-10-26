#!/usr/bin/env ruby
#-*- coding: utf-8 -*-

require 'rubygems'
require 'bundler/setup'

require 'json'
require 'uri'
require 'faye/websocket'
require 'sinatra/base'
require 'thin'

Faye::WebSocket.load_adapter('thin')

class Player
  attr_accessor :id,:name,:socket,:x,:y,:rotate,:bullet,:width,:height, :frame, :up, :shooted, :bonus
  @@instances = 0
  def initialize(socket,name,x,y)
    @@instances += 1
    @id = @@instances
    @name = name
    @x = x
    @y = y
    @rotate = 0
    @socket = socket
    @width = 100
    @height = 100
    @frame = 0
    @up = true
    @speed_up = 0
    @speed_lp = 0
    @grawity = 0.1
    @shooted = 0
    @bonus = nil
    @max_speed = 20
  end
  def reset()
    @x = 50*Random.rand(50)
    @y = 50*Random.rand(50)
    @speed_up = 0
    @speed_lp = 0
    @grawity = 0.1
  end
  def update(direction)
    if direction == 'l'
      @speed_lp -= 1 if @speed_lp > -@max_speed
      @speed_lp = -1 if @bonus == 0 
      @rotate = 1
    end
    if direction == 'r'
      @speed_lp += 1.5 if @speed_lp < @max_speed
      @speed_lp = 1 if @bonus == 0 
      @rotate = 0
    end
    @grawity -= 1 if direction == 't' && @grawity > - 2
    @speed_lp = 0 if direction == 'b' && @speed_up < 2
  end
  def grow(bullet)
    $map.players.each {|p| p.shooted += 1 if p.bullet == bullet}
    $map.players.each {|p| p.bullet = nil if p.bullet == bullet}
    @width += 10 if @width < 150
    @height += 10 if @height < 150
    self.reset()
  end
  def move()
    @grawity = @grawity +  0.025 if @grawity < 2
    @y += @grawity
    @x = @x + @speed_lp
  end
  def setbonus(id,bonus)
    @bonus = id
    @socket.send "Ciężka miłość"
    @speed_lp = 0
    $map.bonuses.each {|b| b.move() if b == bonus}
  end
end

class Bullet
  attr_accessor :x,:y,:diff,:a,:b,:aunit,:bunit
  def initialize(player,coordinates1,coordinates2)
    @player = player
    @x = coordinates1[0]+20
    @y = coordinates1[1]+20
    @diff = [coordinates2[0]-coordinates1[0], coordinates2[1]-coordinates1[1]]
    self.unit()
  end
  def distance
    @a = @diff[0]
    @b = @diff[1]
    return Math.sqrt(@a**2 + @b**2)
  end
  def unit
    distance = self.distance()
    if distance.zero?
      @aunit = 1.0
      @bunit = 0.0
      return [@aunit, @bunit]
    end
    @aunit = @a/distance
    @bunit = @b/distance
    return [@aunit,@bunit]
  end
  def update
    @x += @aunit*20
    @y += @bunit*20
    $map.players.each {|p| p.grow(self) if ((@y > p.y ) && (@y < p.y + p.height) && (@x > p.x ) && (@x < p.x + p.width)) && p!=@player}
  end
end

class Bonus
  attr_accessor :x,:y,:type
  def initialize(x,y,type)
    @x = x
    @y = y
    @size_x = 50
    @size_y = 50
    @type = type
  end
  def move()
    @x = 50*Random.rand(50)
    @y = 50*Random.rand(50)
  end
  def update()
    $map.players.each {|p| p.setbonus(@type,self) if ((@y > p.y ) && (@y < p.y + p.height) && (@x > p.x ) && (@x < p.x + p.width)) && p!=@player && type == 0 }
  end
end

class Map
  attr_accessor :players, :bonuses
  def initialize()
    @players = []
    @bonuses = []
  end
  def update
    if Time.now().to_ms - $previous_time.to_ms > 16
      $map.players.each do |player|
        player.move()
        player.frame +=1 if (player.frame < 50 && player.up==true)
        if (player.frame == 50 && player.up==true)
          player.frame = 49
          player.up = false
        end
        player.frame -=1 if (player.frame > 0 && player.up==false) 
        if (player.frame == 0 && player.up==false)
          player.frame = 1
          player.up = true
        end
        player.bullet.update if !(player.bullet==nil)
        player.bonus = nil if Random.rand(500) < 10 && player.bonus != nil
      end
      @bonuses.each {|b| b.update()}
      @bonuses << Bonus.new(50*Random.rand(50),50*Random.rand(50),0) if @bonuses.size < 10 
      $previous_time = Time.now()
    end
    ids = Array.new
    @players.each{|p| ids << p.id}
    names = Array.new
    @players.each{|p| names << p.name}
    coordinates = Array.new
    @players.each{|p| coordinates << [p.x,p.y]}
    sizes = Array.new
    @players.each{|p| sizes << [p.width,p.height]}
    rotates = Array.new
    @players.each{|p| rotates << p.rotate}
    frames = Array.new
    @players.each{|p| frames << p.frame}
    shooted = Array.new
    @players.each{|p| shooted << p.shooted}
    bullets = Array.new
    @players.each{|p| bullets << [p.bullet.x(),p.bullet.y()] if !(p.bullet==nil)} 
    bonuses = Array.new
    @bonuses.each{|b| bonuses << [b.x,b.y,b.type] } 
    dane = {:id => ids, :name => names, :coordinates => coordinates, :rotates => rotates, :sizes => sizes, 
      :bullets => bullets, :frames => frames, :shooted => shooted, :bonuses =>bonuses}.to_json
  end
end

class Time
  def to_ms
    (self.to_f * 1000.0).to_i
  end
end

$previous_time = Time.now()
$map = Map.new()

class App < Sinatra::Base
  set :environment, ENV.fetch('RACK_ENV', 'production').to_sym
  set :root, File.expand_path(__dir__)

  get '/' do
    erb :index
  end

  get '/healthz' do
    content_type :json
    {status: 'ok', players: $map.players.size}.to_json
  end
end

class WebSocketApp
  def call(env)
    return App.call(env) unless env['PATH_INFO'] == '/ws'
    unless Faye::WebSocket.websocket?(env)
      return [426, {'content-type' => 'text/plain', 'upgrade' => 'websocket'}, ['WebSocket required']]
    end
    if env['HTTP_ORIGIN']
      begin
        origin = URI.parse(env['HTTP_ORIGIN'])
        expected = URI.parse("#{origin.scheme}://#{env['HTTP_HOST']}")
        unless %w[http https].include?(origin.scheme) && origin.host == expected.host && origin.port == expected.port
          return [403, {'content-type' => 'text/plain'}, ['Origin rejected']]
        end
      rescue URI::InvalidURIError
        return [403, {'content-type' => 'text/plain'}, ['Origin rejected']]
      end
    end

    socket = Faye::WebSocket.new(env, nil, ping: 25, max_length: 4096)
    player = nil
    socket.on :open do |_event|
      if $map.players.size >= 25
        socket.close(1008, 'Room full')
      else
        player = Player.new(socket, '', 50 * Random.rand(5), 50 * Random.rand(5))
        $map.players << player
      end
    end
    socket.on :message do |event|
      next unless player && event.data.is_a?(String)
      mess = event.data
      case mess
      when 'i'
        socket.send "i:#{player.id}"
      when 'j'
        # Each client requests its own snapshot. Avoid the old N-squared broadcast.
        socket.send "j:#{$map.update()}"
      when 'l', 'r', 't', 'b'
        player.update(mess)
      when 'q'
        player.reset()
      when /\Ap/
        values = mess[1..].split(',', -1)
        next unless values.size == 2
        coordinates = values.map { |value| Float(value, exception: false) }
        next unless coordinates.all? { |value| value && value.finite? && value.abs <= 10_000_000 }
        player.bullet = Bullet.new(player, [player.x, player.y], coordinates)
      when /\An(.{2,30})\z/m
        player.name = Regexp.last_match(1).strip
      when /\Am(.{1,500})\z/m
        message = Rack::Utils.escape_html("#{player.name}: #{Regexp.last_match(1)}")
        $map.players.each { |other| other.socket.send(message) }
      end
    end
    socket.on(:close) { |_event| $map.players.delete(player) }
    socket.rack_response
  end
end

if $PROGRAM_NAME == __FILE__
  Thin::Server.new(ENV.fetch('BIND', '0.0.0.0'), Integer(ENV.fetch('PORT', '8080')), WebSocketApp.new).start
end
