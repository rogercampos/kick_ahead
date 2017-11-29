$LOAD_PATH.unshift File.expand_path("../../lib", __FILE__)
require "kick_ahead"

require "minitest/autorun"
require 'timecop'

class BaseTest < Minitest::Test
  class InMemoryRepository
    def initialize
      @id = '1'
      @data = {}
    end

    def delete(id)
      @data.delete(id)
    end

    def create(klass, schedule_at, *args)
      @data[@id] = [klass, schedule_at, args]
      @id.tap { @id = @id.succ }
    end

    def each_job_in_the_past
      @data.select { |_k, v| v[1] < Time.now }.each do |k, v|
        yield(
            id: k,
            job_class: v[0],
            job_args: v[2],
            scheduled_at: v[1]
        )
      end
    end

    def size
      @data.keys.size
    end
  end

  # Separate tests from util methods
  def self.test(name, &block)
    test_name = "test_#{name.gsub(/\s+/, '_')}".to_sym
    defined = method_defined? test_name
    raise "#{test_name} is already defined in #{self}" if defined
    if block_given?
      define_method(test_name, &block)
    else
      define_method(test_name) do
        flunk "No implementation provided for #{name}"
      end
    end
  end

  def setup
    @tick_interval = 10 * 60
    @old_tick_interval = KickAhead.tick_interval
    @old_repository = KickAhead.repository
    KickAhead.tick_interval = @tick_interval
    KickAhead.repository = repository
    KickAhead.current_time = -> { Time.now }

    super
  end

  def teardown
    KickAhead.tick_interval = @old_tick_interval
    KickAhead.repository = @old_repository

    super
  end
end