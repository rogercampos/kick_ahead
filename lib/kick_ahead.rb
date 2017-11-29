# frozen_string_literal: true

require "kick_ahead/version"
require "kick_ahead/job"

module KickAhead
  OutOfInterval = Class.new(StandardError)
  NoTickIntervalConfigured = Class.new(RuntimeError)

  RAISE_EXCEPTION_STRATEGY = :raise_exception
  IGNORE_STRATEGY = :ignore
  HOOK_STRATEGY = :hook

  ALL_STRATEGIES = [RAISE_EXCEPTION_STRATEGY, IGNORE_STRATEGY, HOOK_STRATEGY].freeze

  class << self
    attr_accessor :tick_interval
    attr_accessor :repository
    attr_accessor :current_time

    def tick
      if tick_interval.nil?
        raise NoTickIntervalConfigured, 'No tick_interval configured! Please set `KickAhead.tick_interval`'
      end

      if current_time.nil?
        raise 'You must configure a way for me to know the current time!'
      end

      KickAhead.repository.each_job_in_the_past do |job|
        if job[:scheduled_at] < KickAhead.current_time.call - tick_interval - constantize(job[:job_class]).tolerance
          out_of_time_job(job)
        else
          run_job(job)
        end
      end
    end

    def run_job(job)
      constantize(job[:job_class]).new.perform(*job[:job_args])
      KickAhead.repository.delete(job[:id])
    end

    def out_of_time_job(job)
      case constantize(job[:job_class]).out_of_time_strategy.to_sym
        when RAISE_EXCEPTION_STRATEGY
          raise OutOfInterval, "The job of class #{job[:job_class]} with args #{job[:job_args].inspect} "\
                          'was not possible to run because of an out of interval tick '\
                          "(we didn't receive a tick in time to run it) and it's maximum tolerance "\
                          'threshold is also overdue.'

        when IGNORE_STRATEGY
          KickAhead.repository.delete(job[:id])

        when HOOK_STRATEGY
          constantize(job[:job_class]).new.out_of_time_hook(job[:scheduled_at], *job[:job_args])
          KickAhead.repository.delete(job[:id])

        else
          raise 'Invalid strategy'
      end
    end

    private

    # Extracted from activesupport/lib/active_support/inflector/methods.rb, line 258
    def constantize(camel_cased_word)
      names = camel_cased_word.split("::".freeze)

      # Trigger a built-in NameError exception including the ill-formed constant in the message.
      Object.const_get(camel_cased_word) if names.empty?

      # Remove the first blank element in case of '::ClassName' notation.
      names.shift if names.size > 1 && names.first.empty?

      names.inject(Object) do |constant, name|
        if constant == Object
          constant.const_get(name)
        else
          candidate = constant.const_get(name)
          next candidate if constant.const_defined?(name, false)
          next candidate unless Object.const_defined?(name)

          # Go down the ancestors to check if it is owned directly. The check
          # stops when we reach Object or the end of ancestors tree.
          constant = constant.ancestors.inject(constant) do |const, ancestor|
            break const    if ancestor == Object
            break ancestor if ancestor.const_defined?(name, false)
            const
          end

          # owner is in Object, so raise
          constant.const_get(name, false)
        end
      end
    end
  end
end
