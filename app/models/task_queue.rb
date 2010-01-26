class Task < Ohm::Model
  include Comparable

  attribute :url
  attribute :eta
  attribute :params
  attribute :params_string
  attribute :queue_name

  index :url
  index :eta
  index :params
  index :params_string
  index :queue_name

  def self.create(*args)
    #args[0][:params_string] = args[0][:params].to_s if args[0][:params] # a hack for now - for unique tasks...
    model = super
    model.eta = Time.now.to_s unless model.eta
    model.eta.to_f
    model.save
    model
  end

  def validate
    #assert_unique [:url, :params_string, :queue_name] # a hack for now - for unique tasks...
  end

  def to_s
    YAML.dump(self)
  end

  def self.from_s(value)
    return nil if value.nil?

    model = YAML.load(value)
    model.eta = Time.at(model.eta.to_f)
    model.eta.to_s
    model
  end

  def <=> other
    other.id <=> id
  end
end

class Que < Ohm::Model

  attribute :queue_name
  list :tasks
  index :queue_name

  def self.by_queue_name(queue_name)
    hash = { :queue_name => queue_name }
    self.find(hash).first
  end

end

class TaskQueue

  def self.add(queue_name, task)

    return nil if task.nil? or task.errors.size > 0

    queue = Que.by_queue_name(queue_name)
    unless queue
      queue = Que.create(:queue_name => queue_name)
    end

    task.queue_name = queue.queue_name
    task.save

    if task.errors.size > 0
      task.delete
    else
      queue.tasks << task.to_s
      queue.save
    end

  end

  def self.next(queue_name)
    queue = Que.by_queue_name(queue_name)
    if queue
      task = queue.tasks.shift
      task = Task.from_s(task) if task
      task.delete if task
    end
  end

  def self.all(queue_name)
    queue = Que.by_queue_name(queue_name)
    if queue
      queue.tasks.all.collect do |task|
        Task.from_s(task)
      end
    else
      []
    end
  end

  def self.any()
    queues = Que.all
    tasks = []
    if queues
      queues.each do |queue|
        task = queue.tasks.shift
        task = Task.from_s(task) if task
        task.delete if task
        tasks << task if task
      end
    end
    tasks
  end

  def self.clear_all
    Que.all.each {|q| q.tasks.clear }
  end

end
