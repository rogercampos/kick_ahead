# frozen_string_literal: true

require "test_helper"

class KickAheadTest < BaseTest
  PROOFS = {}

  class MyJob < KickAhead::Job
    def perform(x)
      raise RuntimeError if x =~ /FAIL/

      PROOFS[x] = 'Job done!'
    end

    def out_of_time_hook(scheduled_at, x)
      PROOFS[x] = "Out of time!. Scheduling was: #{scheduled_at}"
    end
  end

  class SubJob < MyJob
  end

  def repository
    @repository ||= InMemoryRepository.new
  end

  def setup
    super
    MyJob.tolerance = 0
    MyJob.out_of_time_strategy = :raise_exception
  end

  def teardown
    PROOFS.clear
  end

  test 'tick raises error if interval not configured' do
    KickAhead.tick_interval = nil
    assert_raises(KickAhead::NoTickIntervalConfigured) { KickAhead.tick }
  end

  test 'executes with a delta on given time' do
    MyJob.run_in 3600, 'delta_basic_test'

    assert_equal 1, repository.size

    Timecop.travel Time.now + 50 * 60 do
      KickAhead.tick

      assert_nil PROOFS['foo']
    end

    Timecop.travel Time.now + 3600 + @tick_interval / 2 do
      KickAhead.tick

      assert_equal 'Job done!', PROOFS['delta_basic_test']
      assert_equal 0, repository.size
    end
  end

  test 'executes with a time on given time' do
    MyJob.run_at Time.now + 3600, 'time_basic_test'

    assert_equal 1, repository.size

    Timecop.travel Time.now + 50 * 60 do
      KickAhead.tick

      assert_nil PROOFS['foo']
    end

    Timecop.travel Time.now + 3600 + @tick_interval / 2 do
      KickAhead.tick

      assert_equal 'Job done!', PROOFS['time_basic_test']
      assert_equal 0, repository.size
    end
  end

  test 'does not remove the job in case of internal job failure' do
    MyJob.run_in 3600, 'FAIL: this will raise an exception when executed'
    assert_equal 1, repository.size

    Timecop.travel Time.now + 3600 do
      begin
        KickAhead.tick
      rescue RuntimeError
        nil
      end

      assert_equal 1, repository.size
    end
  end

  test 'tolerance configuration can be changed per-class' do
    MyJob.tolerance = 9 * 60

    assert_equal 9 * 60, MyJob.tolerance
    assert_equal 9 * 60, SubJob.tolerance

    SubJob.tolerance = 3 * 3600

    assert_equal 9 * 60, MyJob.tolerance
    assert_equal 3 * 3600, SubJob.tolerance
  end

  test 'still executes if out of time but allowed by tolerance' do
    MyJob.tolerance = 30 * 60

    MyJob.run_in 3600, 'tolerance test'

    Timecop.travel Time.now + 3600 + 25 * 60 do
      KickAhead.tick

      assert_equal 'Job done!', PROOFS['tolerance test']
      assert_equal 0, repository.size
    end
  end

  test 'out_of_time_strategy = :raise_exception => raises error if executed out of time' do
    MyJob.run_in 3600, 'out of time test'
    MyJob.out_of_time_strategy = :raise_exception

    Timecop.travel Time.now + 3600 + @tick_interval + 1 do
      msg = "The job of class MyJob with args 'out of time test' "\
                'was not possible to run because of an out of interval tick '\
                "(we didn't receive a tick in time to run it) and it's maximum tolerance "\
                'threshold is also overdue.'
      assert_raises(KickAhead::OutOfInterval, msg) { KickAhead.tick }
      assert_equal 1, repository.size
    end
  end

  test 'out_of_time_strategy = :ignore => ignores the job if executed out of time' do
    MyJob.run_in 3600, 'out of time test'
    MyJob.out_of_time_strategy = :ignore

    Timecop.travel Time.now + 3600 + @tick_interval + 1 do
      KickAhead.tick
      assert_nil PROOFS['out of time test']
      assert_equal 0, repository.size
    end
  end

  test 'out_of_time_strategy = :hook => runs the job hook' do
    time = Time.now + 3600
    MyJob.run_at time, 'out of time test'
    MyJob.out_of_time_strategy = :hook

    Timecop.travel Time.now + 3600 + @tick_interval + 1 do
      KickAhead.tick
      assert_equal "Out of time!. Scheduling was: #{time}", PROOFS['out of time test']
      assert_equal 0, repository.size
    end
  end
end
