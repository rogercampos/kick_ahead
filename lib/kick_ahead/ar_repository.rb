class ArRepository
  def initialize(klass)
    @klass = klass
  end

  def each_job_in_the_past
    @klass.where('scheduled_at <= ?', KickAhead.current_time.call).find_each do |job|
      yield(as_hash(job))
    end
  end

  def create(job_class, schedule_at, *args)
    job = @klass.create! job_class: job_class, job_args: args, scheduled_at: schedule_at
    job.id
  end

  def delete(id)
    raise 'Not possible!' if id.nil?
    @klass.find(id).delete
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