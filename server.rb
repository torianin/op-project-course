#!/usr/bin/env ruby
#-*- coding: utf-8 -*-

require 'rubygems'
require 'bundler/setup'

require 'em-websocket'
require 'sinatra/base'
require 'thin'

require 'coffee-script'

module Tilt
  class CoffeeScriptTemplate
    def prepare
      @data.force_encoding Encoding.default_external
      if !options.key?(:bare) and !options.key?(:no_wrap)
        options[:bare] = self.class.default_bare
      end
    end
  end
end

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

EventMachine.run do
  $previous_time = Time.now()
  $map = Map.new()

  class App < Sinatra::Base
      get '/' do
          erb :index
      end
      get "/application.js" do
          coffee :application
      end
  end

  EventMachine::WebSocket.start(:host => "0.0.0.0", :port => 8080) do |socket|
    socket.onopen do
      puts "dołączył nowy gracz" 
      $map.players << Player.new(socket,"",50*Random.rand(5),50*Random.rand(5)) if $map.players.size < 25
    end
    socket.onmessage do |mess|
      $map.players.each {|p| p.socket.send "i:#{p.id}" if p.socket == socket && mess == 'i'}
      $map.players.each {|p| $map.players.each {|s| s.socket.send "j:#{$map.update()}"} if mess[0] == 'j'}
      $map.players.each {|p| p.update(mess) if p.socket == socket && mess == 'l'}
      $map.players.each {|p| p.update(mess) if p.socket == socket && mess == 'r'}
      $map.players.each {|p| p.update(mess) if p.socket == socket && mess == 't'}
      $map.players.each {|p| p.update(mess) if p.socket == socket && mess == 'b'}
      $map.players.each {|p| p.reset() if p.socket == socket && mess == 'q'}
      $map.players.each {|p| p.bullet = Bullet.new(p,[p.x,p.y], mess[1..mess.size].split(",").map(&:to_i)) if p.socket == socket && mess[0] == 'p'}
      $map.players.each {|p| $map.players.each {|s| s.socket.send "#{p.name}: #{mess[1..mess.size]}"} if p.socket == socket && mess[0] == 'm'}
      $map.players.each {|p| p.name = mess[1..mess.size] if p.socket == socket && mess[0] == 'n'}
    end
    socket.onclose do
      puts "gracz odszedl"
      $map.players.each {|p| $map.players.delete(p) if p.socket == socket}
    end
  end
  
  App.run!(:bind => "127.0.0.1", :port => 8081)
end
