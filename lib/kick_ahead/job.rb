# frozen_string_literal: true

module KickAhead
  class Job
    # Simplified version extracted from ActiveSupport
    def self.class_attribute(name)
      define_singleton_method(name) { nil }

      ivar = "@#{name}"

      define_singleton_method("#{name}=") do |val|
        singleton_class.class_eval do
          define_method(name) { val }
        end

        if singleton_class?
          class_eval do
            define_method(name) do
              if instance_variable_defined? ivar
                instance_variable_get ivar
              else
                singleton_class.send name
              end
            end
          end
        end
        val
      end
    end

    class_attribute :tolerance
    class_attribute :out_of_time_strategy

    self.tolerance = 0
    self.out_of_time_strategy = :raise_exception

    def self.run_in(delta, *args)
      KickAhead.repository.create(name, KickAhead.current_time.call + delta, *args)
    end

    def self.run_at(time, *args)
      KickAhead.repository.create(name, time, *args)
    end

    def perform(*)
      raise NotImplementedError
    end
  end
end
