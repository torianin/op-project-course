#!/usr/bin/env ruby
#-*- coding: utf-8 -*-

require 'rubygems'
require 'bundler/setup'

require 'em-websocket'
require 'sinatra/base'
require 'thin'

require 'coffee-script'
require 'json'

class Player
  attr_accessor :id,:name,:socket,:x,:y,:rotate,:bullet,:width,:height
  @@instances = 0
  def initialize(socket,name,x,y)
    @@instances += 1
    @id = @@instances
    @name = name
    @x = x
    @y = y
    @rotate = 0
    @socket = socket
    @width = 60
    @height = 60
  end
  def update(direction)
    if direction == 'l'
      @x -= 50 
      @rotate = 1
    end
    if direction == 'r'
      @x += 50
      @rotate = 0
    end
    @y -= 50 if direction == 't'
    @y += 50 if direction == 'b'
  end
  def grow(bullet)
    $map.players.each {|p| p.bullet = nil if p.bullet == bullet}
    @width += 10 if @width < 120
    @height += 10 if @height < 120
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
    bullets = Array.new
    @players.each{|p| bullets << [p.bullet.x(),p.bullet.y()] if !(p.bullet==nil)} 
    dane = {:id => ids, :name => names, :coordinates => coordinates, :rotates => rotates, :sizes => sizes, :bullets => bullets}.to_json
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
      puts "dolaczyl nowy gracz" 
      $map.players << Player.new(socket,"",50*Random.rand(5),50*Random.rand(5)) if $map.players.size < 10
    end
    socket.onmessage do |mess|
      specials = ['l','r','t','b','m','p','i','j']
      $map.players.each {|p| p.socket.send "i:#{p.id}" if p.socket == socket && mess == 'i'}
      $map.players.each {|p| $map.players.each {|s| s.socket.send "j:#{$map.update()}"} if mess[0] == 'j'}
      $map.players.each {|p| p.update(mess) if p.socket == socket && mess == 'l'}
      $map.players.each {|p| p.update(mess) if p.socket == socket && mess == 'r'}
      $map.players.each {|p| p.update(mess) if p.socket == socket && mess == 't'}
      $map.players.each {|p| p.update(mess) if p.socket == socket && mess == 'b'}
      $map.players.each {|p| p.bullet = Bullet.new(p,[p.x,p.y], mess[1..mess.size].split(",").map(&:to_i)) if p.socket == socket && mess[0] == 'p'}
      $map.players.each {|p| $map.players.each {|s| s.socket.send "#{p.name}: #{mess[1..mess.size]}"} if p.socket == socket && mess[0] == 'm'}
      $map.players.each {|p| p.name = mess if p.socket == socket && !specials.include?(mess[0])}
    end
    socket.onclose do
      puts "gracz odszedl"
      $map.players.each {|p| $map.players.delete(p) if p.socket == socket}
    end
  end
  
  App.run!(:bind => "127.0.0.1", :port => 8081)
end

