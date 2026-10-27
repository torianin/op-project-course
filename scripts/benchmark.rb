# frozen_string_literal: true

require 'benchmark'
require 'json'
require_relative '../lib/game'

world = FatAngel::World.new(random: Random.new(1))
25.times { |index| world.join(index + 1, "Player#{index + 1}") }
requests = 10_000
world.snapshot_packet # Warm the shared snapshot cache.
before = world.snapshot_encodes
cached = Benchmark.realtime { requests.times { world.snapshot_packet } }
cached_encodes = world.snapshot_encodes - before
before = world.snapshot_encodes
uncached = Benchmark.realtime { requests.times { world.snapshot_packet(refresh: true) } }
uncached_encodes = world.snapshot_encodes - before
puts JSON.pretty_generate(
  players: world.players.size, snapshot_reads: requests,
  cached_seconds: cached.round(6), cached_json_encodes: cached_encodes,
  uncached_seconds: uncached.round(6), uncached_json_encodes: uncached_encodes,
  note: 'Snapshot microbenchmark only; excludes physics, network and browser rendering.'
)
