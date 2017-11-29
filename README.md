# KickAhead

Allows you to push code to be executed in the future. The code is organized in Jobs with the same API
sidekiq has:

```ruby
class MyJob < KickAhead::Job
  def perform(some, args)
    # Your code
  end
end
```

```ruby
MyJob.run_in 3600, "some", "args"
MyJob.run_at Time.now + 2 * 3600, "some", "args"
```

This library is minimalist and the user must provide a persistent storage system as well as a polling 
mechanism, that will be used to control the timings.


## Installation

Add this line to your application's Gemfile:

```ruby
gem 'kick_ahead'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install kick_ahead

## Usage


First, you need to provide a polling mechanism that allows you to call `KickAhead.tick` at regular intervals. 
This interval must be also configured at `KickAhead.tick_interval`. You application can call `tick` more 
frequently than what you establish here, but never less frequently. If your polling source is not accurate
but have a predictable behavior / margin of error, configure the `tick_interval` to be your maximum possible 
frequency even if your real polling source frequency is usually higher.

If you fail to call `tick` frequently enough, you may have dropped jobs (see below).

Also importantly, your call to `tick` must be atomic in your application. Only one `tick` must be in execution
at any given time. You must use some sort of locking mechanism to ensure this, like ruby's `Mutex#synchronize`
if you only have one process that may tick in your application, or some other application-wide lock mechanism 
otherwise (i.e. using redis or postgres advisory locks).

You'll also need to provide a Repository object, to offer a persistent storage (see below in Configuration).

The basic idea is that you write code in Jobs, and then "push" those jobs to be executed at some point in the
future. Examples:

```ruby
MyJob.run_in 3600, "some", "args"
MyJob.run_at Time.now + 2 * 3600, "some_args"
```

This lib guarantees that your job will be executed between your given time and your given time + your configured
tick_interval at most. If you want more precision, you'll need to decrease your tick_interval.

If, for some reason, your polling fail and the `tick` method is not called for a long time, any job that
was configured to run during that time will not run as expected. On the next tick, we'll detect those 
stale jobs and then the following may occur:

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
can be configured on a per job basis and by default is "raise_exception". The options are:

- `raise_exception`: An exception will be raised. The job is kept in the repository, waiting for an external
action to correct the situation (remove the job, change it's schedule time, etc.). The exception gives 
information about the job class and arguments. No further jobs will be executed until this is corrected.

- `ignore`: The out of time jobs will be simply deleted with no execution.

- `hook`: In this case, the method `out_of_time_hook` will be called on the job instance in the same way
the `perform` method would, giving you the change to do specific logics. The first argument, however, will be the
original scheduling time, so you can perform comparisons with this information. 

Configure it with:

```ruby
class MyJob < KickAhead::Job
  # self.out_of_time_strategy = :raise_exception
  # self.out_of_time_strategy = :ignore
  self.out_of_time_strategy = :hook
  
  def perform(some, args)
    # Your code
  end
  
  def out_of_time_hook(scheduled_at, some, args)
    # Your code when out of time
  end
end
```

In case an exception occurs inside your Job, nothing extraordinary will happen. Kick Ahead will not capture
the exception, any other possible jobs will not be processed.

Your jobs are expected to be quick. If a heavy work has to be done, delegate it to the background.


## Configuration

### Polling interval

`KickAhead.tick_interval = 3600`

This value must be set to the expected polling interval, in seconds. In the example, the polling frequency
is 1 hour. Your code is then expected to call:

`KickAhead.tick`

every hour. 


### Repository

You're also expected to provide a repository to implement persistence over the data used to store jobs.

A repository is any object that responds to the following methods:

- `create(klass, schedule_at, *args)`: Used to create a new job. `klass` is a string representing the
 job class, `schedule_at` is a datetime representing the moment in time when this is expected to be executed,
 and `*args` is an expandable list of arguments (you can use json columns in postgres to store those easily).
 
 This method is expected to return an identifier as a string, whatever you want that to be, so that it can be
 used in the future to reference this job in the persistent repository.
 
- `each_job_in_the_past`: Returns a collection of job objects (hashes). In no particular order, but always
jobs that are in the past respect current time. Kick Ahead will then either execute or discard them depending
on the configurations.

    A job is a hash with the following properties, example:
    
    ```ruby
        {
          id: "11",
          job_class: "MyJob",
          job_args: [1, "foo"],
          scheduled_at: Time.new(2017, 1, 1, 1, 1, 1)
        }
    ``` 
    
    - id: The identifier you gave to the job
    - job_class: same first argument of the `create` call.
    - job_args: same third argument of the `create` call.
    - scheduled_at: same second argument of the `create` call.

- `delete(id)`: Used to remove a job from the persistent storage. The given "id" is the identifier of the
job as returned by the `create` or `each_job_in_the_past` methods.


### Current time

Since this library is heavily based on time, it cannot make any assumption about how are you managing
the time in your application. Ruby's default behavior is to return the system time, but for a distributed
application that may run in different machines this is usually not desirable, and instead you should instead use
some other way to get the current time (i.e. rails `Time.current`).

Since this is a choice of the host app, you must also configure how KickAhead should get the current time by
providing a lambda to return it.

```ruby
KickAhead.current_time = -> { Time.current }
```

This way you can control what is considered to be the current time, and then make sure that this value is consistent
with the `each_job_in_the_past` method in the repository, so time comparisons work as expected.


### Repository example with ActiveRecord

```ruby
# create_table "kick_ahead_jobs", force: :cascade do |t|
#   t.string "job_class", null: false
#   t.jsonb "job_args", null: false
#   t.datetime "scheduled_at", null: false
#   t.index ["scheduled_at"], name: "index_kick_ahead_jobs_on_scheduled_at"
# end
class KickAheadJob < ActiveRecord::Base
end

module RepositoryExample
  extend self

  def each_job_in_the_past
    KickAheadJob.where('scheduled_at <= ?', Time.current).find_each do |job|
      yield(as_hash(job))
    end
  end

  def create(klass, schedule_at, *args)
    job = KickAheadJob.create! job_class: klass, job_args: args, scheduled_at: schedule_at
    job.id
  end

  def delete(id)
    KickAheadJob.find(id).delete
  end

  private

  def as_hash(job)
    {
      id: job.id,
      job_class: job.job_class,
      job_args: job.job_args,
      scheduled_at: job.scheduled_at
    }
  end
end

```

## FAQS

Q: What If I don't care about jobs executing out of time? I want the job to execute after time X, but after that, I
don't need to be specific (ej: fail if the time doesn't fit). 

A: You can set the tolerance value to an incredible high value (ie: 300 years).


## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake test` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/rogercampos/kick_ahead.
