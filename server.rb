#!/usr/bin/env ruby
# frozen_string_literal: true

require 'bundler/setup'
require_relative 'lib/server'

if $PROGRAM_NAME == __FILE__
  Thin::Server.new(
    ENV.fetch('BIND', '0.0.0.0'),
    Integer(ENV.fetch('PORT', '8080')),
    FatAngel::WebSocketApp.new
  ).start
end
