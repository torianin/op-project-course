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
  attr_accessor :id,:name,:socket,:x,:y,:rotate,:bullet,:width,:height, :frame, :up
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
  end
  def update(direction)
    if direction == 'l'
      @speed_lp -= 1 if @speed_lp > -10
      @rotate = 1
    end
    if direction == 'r'
      @speed_lp += 1.5 if @speed_lp < 10
      @rotate = 0
    end
    @grawity -= 1 if direction == 't' && @grawity > - 2
    @speed_lp = 0 if direction == 'b' && @speed_up < 2
  end
  def grow(bullet)
    $map.players.each {|p| p.bullet = nil if p.bullet == bullet}
    @width += 10 if @width < 120
    @height += 10 if @height < 120
  end
  def move()
    @grawity = @grawity +  0.025 if @grawity < 2
    @y += @grawity
    @x = @x + @speed_lp
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

class Map
  attr_accessor :players
  def initialize()
    @players = []
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
      end
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
    bullets = Array.new
    #K
    bullets << [130,70] << [130,140] << [130,210]  << [130,280]
    bullets << [170,175] 
    bullets << [210,140] << [210,210]
    bullets << [260,70]  << [260,280]
    #O
    bullets << [400,70] << [350,140] << [350,210]  << [400,280]
    bullets << [450,70] << [500,140] << [500,210]  << [450,280]
    #C
    bullets << [650,70] << [600,140] << [600,210]  << [650,280]
    bullets << [700,70] << [700,280]
    #H
    bullets << [800,70] << [800,140] << [800,210]  << [800,280]
    bullets << [850,175] << [900,175]
    bullets << [950,70] << [950,140] << [950,210]  << [950,280]
    #A
    bullets << [1100,70] << [1075,140] << [1050,210]  << [1050,280]
    bullets << [1100,175] << [1150,175]
    bullets << [1150,70] << [1175,140] << [1200,210]  << [1200,280]
    #M
    bullets << [1300,70] << [1300,140] << [1300,210]  << [1300,280]
    bullets << [1350,140]
    bullets << [1400,210] 
    bullets << [1450,140]
    bullets << [1500,70] << [1500,140] << [1500,210]  << [1500,280]
    #C
    bullets << [1850,70] << [1800,140] << [1800,210]  << [1850,280]
    bullets << [1900,70] << [1900,280]
    #I
    bullets << [2000,70] << [2000,140] << [2000,210]  << [2000,280]
    #E
    bullets << [2100,70] << [2100,140] << [2100,210]  << [2100,280]
    bullets << [2150,175] << [2200,175]
    bullets << [2150,70] << [2200,70]
    bullets << [2150,280] << [2200,280]
    bullets << [2200,340]
    @players.each{|p| bullets << [p.bullet.x(),p.bullet.y()] if !(p.bullet==nil)} 
    dane = {:id => ids, :name => names, :coordinates => coordinates, :rotates => rotates, :sizes => sizes, :bullets => bullets, :frames => frames}.to_json
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
      $map.players << Player.new(socket,"",50*Random.rand(5),50*Random.rand(5)) if $map.players.size < 10
    end
    socket.onmessage do |mess|
      $map.players.each {|p| p.socket.send "i:#{p.id}" if p.socket == socket && mess == 'i'}
      $map.players.each {|p| $map.players.each {|s| s.socket.send "j:#{$map.update()}"} if mess[0] == 'j'}
      $map.players.each {|p| p.update(mess) if p.socket == socket && mess == 'l'}
      $map.players.each {|p| p.update(mess) if p.socket == socket && mess == 'r'}
      $map.players.each {|p| p.update(mess) if p.socket == socket && mess == 't'}
      $map.players.each {|p| p.update(mess) if p.socket == socket && mess == 'b'}
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
