require 'json'

module FatAngel
  VERSION = '0.0.2'.freeze
  TICK_RATE = 60
  SNAPSHOT_RATE = 20

  class Player
    attr_accessor :name, :x, :y, :bullet, :bonus, :score, :size
    attr_reader :id, :rotate, :frame, :respawns

    def initialize(id, name, random)
      @id, @name = id, name
      @x, @y = random.rand(5) * 50.0, random.rand(5) * 50.0
      @speed_x, @gravity = 0.0, 0.1
      @rotate, @frame, @frame_direction = 0, 0, 1
      @size, @score, @respawns = 100, 0, 0
      @bullet = @bonus = nil
    end

    def control(command)
      case command
      when 'l'
        @speed_x = @bonus == 0 ? -1.0 : [@speed_x - 1.0, -20.0].max
        @rotate = 1
      when 'r'
        @speed_x = @bonus == 0 ? 1.0 : [@speed_x + 1.5, 20.0].min
        @rotate = 0
      when 't' then @gravity = [@gravity - 1.0, -2.0].max
      when 'b' then @speed_x = 0.0
      end
    end

    def reset(random)
      @x, @y = random.rand(50) * 50.0, random.rand(50) * 50.0
      @speed_x, @gravity = 0.0, 0.1
      @respawns += 1
    end

    def step(random)
      @gravity = [@gravity + 0.025, 2.0].min
      @x += @speed_x
      @y += @gravity
      @frame += @frame_direction
      @frame_direction = -1 if @frame == 49
      @frame_direction = 1 if @frame.zero?
      @bonus = nil if !@bonus.nil? && random.rand(500) < 10
    end

    def contains?(x, y)
      x > @x && x < @x + @size && y > @y && y < @y + @size
    end

    def collect_bonus
      @bonus, @speed_x = 0, 0.0
    end
  end

  class Bullet
    LIFETIME_TICKS = 5 * TICK_RATE
    attr_reader :x, :y

    def initialize(player, target)
      @x, @y = player.x + 20.0, player.y + 20.0
      dx, dy = target[0] - player.x, target[1] - player.y
      length = Math.hypot(dx, dy)
      @velocity_x, @velocity_y = length.zero? ? [20.0, 0.0] : [dx / length * 20.0, dy / length * 20.0]
      @age = 0
    end

    def step
      @x += @velocity_x
      @y += @velocity_y
      @age += 1
    end

    def expired?
      @age >= LIFETIME_TICKS
    end
  end

  class World
    attr_reader :players, :bonuses, :tick, :snapshot_encodes

    def initialize(random: Random.new)
      @random = random
      @players, @bonuses = [], []
      10.times { @bonuses << random_bonus }
      @tick, @snapshot_encodes = 0, 0
      @snapshot = nil
    end

    def join(id, name)
      player = Player.new(id, name, @random)
      @players << player
      invalidate_snapshot
      player
    end

    def leave(player)
      @players.delete(player)
      invalidate_snapshot
    end

    def invalidate_snapshot
      @snapshot = nil
    end

    # Exactly one simulation step, independent of the number of client messages.
    def step
      return if @players.empty?
      @tick += 1
      @players.each { |player| player.step(@random) }
      @players.each do |owner|
        bullet = owner.bullet
        next unless bullet
        bullet.step
        victim = @players.find { |other| !other.equal?(owner) && other.contains?(bullet.x, bullet.y) }
        if victim
          owner.score += 1
          owner.bullet = nil
          victim.size = [victim.size + 10, 150].min
          victim.reset(@random)
        elsif bullet.expired?
          owner.bullet = nil
        end
      end
      @bonuses.each_with_index do |bonus, index|
        collector = @players.find { |player| player.contains?(bonus[0], bonus[1]) }
        next unless collector
        collector.collect_bonus
        yield collector if block_given?
        @bonuses[index] = random_bonus
      end
    end

    # Shared by both push subscribers and legacy snapshot requests. Refresh at 20 Hz.
    def snapshot_packet(refresh: false)
      return @snapshot if @snapshot && !refresh
      state = {id: [], name: [], coordinates: [], sizes: [], rotates: [], frames: [],
               shooted: [], respawns: [], bullets: [], bonuses: @bonuses, tick: @tick}
      @players.each do |player|
        state[:id] << player.id
        state[:name] << player.name
        state[:coordinates] << [player.x, player.y]
        state[:sizes] << [player.size, player.size]
        state[:rotates] << player.rotate
        state[:frames] << player.frame
        state[:shooted] << player.score
        state[:respawns] << player.respawns
        state[:bullets] << [player.bullet.x, player.bullet.y] if player.bullet
      end
      @snapshot_encodes += 1
      @snapshot = "j:#{JSON.generate(state)}".freeze
    end

    private

    def random_bonus
      [@random.rand(50) * 50.0, @random.rand(50) * 50.0, 0]
    end
  end
end
