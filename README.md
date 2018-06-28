# Kick Ahead

Kick Ahead allows you to push code to be executed in the future. The code is organized in Jobs with a simple API:

```ruby
class MyJob < KickAhead::Job
  def perform(some, args)
    # Your code
  end
end

MyJob.run_in 1.hour, "some", "args"
MyJob.run_at 2.hours.from_now, "some_args"
```

This library is minimalist and has no gem dependencies. However, in order to accomplish its task it requires
the host app to provide certain features which this lib depends upon. By expressing dependencies in this
way instead of by "hardcoded" gem dependencies, the user is free to reuse their existing solutions to common
problems.   


## Satisfying requirements

We'll see first what requirements must be satisfied by the app. 


### A Regular clock

The most important thing is to have a regular clock available, which allows you to call code at regular intervals.

Possible solutions to this problem are "plugins" for background systems (like sidekiq-cron for sidekiq),
the traditional cron system in a server, or maybe having an independent process control times with a loop manually
or with rufus-scheduler.

Once you have a regular clock, you must use it to call `KickAhead.tick`. Also, the interval between your clock ticks 
must be specified in `KickAhead.tick_interval` in seconds, for example:

`KickAhead.tick_interval = 3600 # every hour`

Additionally, you must make sure that no two `KickAhead.tick` can be running at the same time across you entire
app (maybe across different servers). 

### A Persistence repository

Next you'll have to provide a persistence layer to store jobs, as a Repository object. A repository is any 
object that responds to the following methods and signatures:

- `create(klass, schedule_at, *args)`: Used to create a new job. `klass` is a string representing the
 job class, `schedule_at` is a datetime representing the moment in time when this is expected to be executed,
 and `*args` is the list of arguments.
 
 This method is expected to return an identifier as a string, whatever you want that to be, so that it can be
 used in the future to reference this job in the persistence repository.
 
- `each_job_in_the_past`: Returns a collection of job objects. In no particular order, but always
jobs that are in the past respect current time. 

A job object is a hash with the following properties, example:

```ruby
    {
      id: "11",
      job_class: "MyJob",
      scheduled_at: Time.new(2017, 1, 1, 1, 1, 1),
      job_args: [1, "foo"]
    }
``` 

   * id: The identifier you gave to the job
   * job_class: same first argument of the `create` call.
   * scheduled_at: same second argument of the `create` call.
   * job_args: same third argument of the `create` call.

- `delete(id)`: Used to remove a job from the persistent storage. The given "id" is the identifier of the
job as returned by the `create` or `each_job_in_the_past` methods.

If you want to use an Active Record model for persistence, you can get an already made repository with this:

```ruby
repository = KickAhead.create_active_record_repository_for(KickAheadJob)
``` 

The table structure must be as follows, taken from a rails schema (note you can name the table and the
model whatever you like):

      create_table "kick_ahead_jobs", force: :cascade do |t|
        t.string "job_class", null: false
        t.jsonb "job_args", null: false
        t.datetime "scheduled_at", null: false
        t.index ["scheduled_at"], name: "index_kick_ahead_jobs_on_scheduled_at"
      end


### Current time

Finally, since this library is heavily based on time, it cannot make any assumption about how are you managing
time in your application. Ruby's default behavior is to return the system time, but for a distributed
application that may run in different machines this is usually not desirable, and instead you might use
some other way to get the current time (like rails `Time.current`).

Since this is a choice of the host app, you must also configure how KickAhead should get the current time by
providing a lambda to return it.

```ruby
KickAhead.current_time = -> { Time.current }
```

This way you can control what is considered to be the current time, and then make sure that this value is consistent
with the `each_job_in_the_past` method in the repository, so time comparisons work as expected.



## Usage

The basic idea is that you write code in Jobs, and then "push" those jobs to be executed at some point in the
future. Examples:

```ruby
class MyJob < KickAhead::Job
  def perform(some, args)
    # Your code
  end
end

MyJob.run_in 1.hour, "some", "args"
MyJob.run_at 2.hours.from_now, "some_args"
```

This lib guarantees that your job will be executed between your given time and your given time + your configured
tick_interval at most. If you want more precision, you'll need to reduce your tick_interval.

If, for some reason, your clock fails and the `tick` method is not called for a long time, any job that
was configured to run during that time will not run as expected. On the next tick, we'll detect those 
stale jobs and then the following logic will apply:

If the job is configured with a `tolerance` value, and we're still inside the tolerance period, the job will 
still run normally. 

Tolerance can be configured from the job class and can be different per job:

```ruby
class MyJob < KickAhead::Job
  self.tolerance = 30.minutes
  
  def perform(some, args)
    # Your code
  end
end
```

Or externally as well:

`MyJob.tolerance = 2.hours`

If tolerance is not satisfied, then the behavior depends on the `out_of_time_strategy` configured. This
can be configured on a per job basis and by default is `raise_exception`. The options are:

- `raise_exception`: An exception will be raised. The job is kept in the repository, waiting for an external
action to correct the situation (remove the job, run it, or fix the situation in some other way). The exception gives 
information about the job class and arguments. No further jobs will be executed until this is corrected.

- `ignore`: The out of time jobs will be simply deleted with no execution.

- `hook`: In this case, the method `out_of_time_hook` will be called on the job instance in the same way
the `perform` method would, giving you the chance to do specific logics. The first argument, however, will be the
original scheduling time, so you can perform comparisons with this information. 

Configure it with:

```ruby
class MyJob < KickAhead::Job
  self.out_of_time_strategy = :raise_exception
  # self.out_of_time_strategy = :ignore
  # self.out_of_time_strategy = :hook
  
  def perform(some, args)
    # Your code
  end
  
  def out_of_time_hook(scheduled_at, some, args)
    # Your code
  end
end
```

In case an exception occurs inside your Job, nothing extraordinary will happen. Kick Ahead will not capture
the exception, any other possible job will not be executed.


## FAQS

- Q: What If I don't care about jobs executing out of time? I want the job to execute after time X, but after that, I
don't need to be specific.

A: You can set the tolerance value to an very high value (ie: 300 years).


## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake test` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/rogercampos/kick_ahead.
