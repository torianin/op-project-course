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
  attr_accessor :id,:name,:socket,:x,:y
  @@instances = 0
  def initialize(socket,name,x,y)
    @@instances += 1
    @id = @@instances
    @name = name
    @x = x
    @y = y
    @socket = socket
  end
end

class Bonus
  def initialize
  end
end

class Map
  @@instances = 0
end

$bonuses = []
$players = []
EventMachine.run do
  class App < Sinatra::Base
      get '/' do
          erb :index
      end
      get "/application.js" do
          coffee :application
      end
      get "/api/map.json" do
          content_type :json
          ids = Array.new
          $players.each{|p| ids << p.id}
          names = Array.new
          $players.each{|p| names << p.name}
          coordinates = Array.new
          $players.each{|p| coordinates << [p.x,p.y]}
          {:id => ids, :name => names, :coordinates => coordinates}.to_json
      end
  end

  EventMachine::WebSocket.start(:host => "0.0.0.0", :port => 8080) do |socket|
    socket.onopen do
      puts "dolaczyl nowy gracz" 
      $players << Player.new(socket,"Robert",0,0) if $players.size < 10
    end
    socket.onmessage do |mess|
      puts "nadaje mu nowe imie" 
      $players.each {|p| p.name = mess if p.socket == socket}
      #$sockets.each {|s| s.send mess}
    end
    socket.onclose do
      puts "gracz odszedl"
      $players.each {|p| $players.delete(p) if p.socket == socket}
    end
  end
  
  App.run!(:bind => '127.0.0.1', :port => 8081)
end

