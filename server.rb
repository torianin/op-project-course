#!/usr/bin/env ruby
#-*- coding: utf-8 -*-

require 'rubygems'
require 'bundler/setup'

require 'em-websocket'
require 'sinatra/base'
require 'thin'

require 'coffee-script'

@sockets = []
@players = []
EventMachine.run do
  class App < Sinatra::Base
      get '/' do
          erb :index
      end
      get "/application.js" do
          coffee :application
      end
  end

  EventMachine::WebSocket.start(:host => "0.0.0.0", :port => 8080) do |ws|
      ws.onopen {
      	  @sockets << ws
          ws.send "Podlaczono"
          if !@players.empty?
          	@players.each {|player| ws.send player}
      	  end
      }

      ws.onmessage { |msg|
   		  @players << msg
          puts "#{msg} podlaczony"
          @sockets.each {|s| s.send msg}
      }

      ws.onclose do
          ws.send "WebSocket zamkniety"
		  @sockets.delete ws
      end

  end
  
  App.run!(:bind => '127.0.0.1', :port => 8081)
end
