require 'rubygems'
require 'em-websocket'
require 'sinatra/base'
require 'thin'

@sockets = []
EventMachine.run do
  class App < Sinatra::Base
      get '/' do
          erb :index
      end
  end

  EventMachine::WebSocket.start(:host => '0.0.0.0', :port => 8080) do |ws| # <-- Added |ws|
      ws.onopen {
      	  @sockets << ws
          ws.send "connected!!!!"
      }

      ws.onmessage { |msg|
          puts "#{msg} podlaczony"
          @sockets.each {|s| s.send msg}
      }

      ws.onclose do
          ws.send "WebSocket closed"
		  @sockets.delete ws
      end

  end
  App.run!({:port => 3000})
end