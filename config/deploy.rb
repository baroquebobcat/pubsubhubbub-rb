role :web, "hostname.com"
role :app, "hostname.com"
role :db,  "hostname.com", :primary => true

set :keep_releases, 5
set :application,   'pubsubhubbub-rb'
set :repository,    'git@github.com:barinek/pubsubhubbub-rb.git'
set :deploy_to,     '/opt/applications/pubsubhubbub-rb'
set :deploy_via,    :copy
set :scm,           :git
set :git_enable_submodules, 1
set :use_sudo, false

default_run_options[:pty] = true

after "deploy:update_code", "deploy:symlink_configs"

namespace :db do
  task :migrate, :roles => :db do
  end
end

namespace :redis do
  task :start, :roles => :app do
    sudo "/opt/redis-1.02/redis-server /opt/redis-1.02/redis.conf"
  end

  task :stop, :roles => :app do
    sudo "killall redis-server"
  end
end

namespace :thin do
  task :start, :roles => :app do
    sudo "/sbin/service thin start"
  end

  task :stop, :roles => :app do
    sudo "killall -v -9 thin"
  end
end

namespace :deploy do
  desc "Start the app"
  task :start, :roles => :app do
  end

  desc "Stop the app"
  task :stop, :roles => :app do
  end

  desc "Restart the app"
  task :restart, :roles => :app do
    thin::stop
    thin::start
  end

  task :symlink_configs, :roles => :app do
    sudo 'rm -f /etc/thin/example.yml'

    sudo 'rm -f /etc/thin/monk_push.yml'
    sudo 'ln -s /opt/applications/monk_push/current/config/thin/monk_push.yml /etc/thin/monk_push.yml'

    sudo 'rm -f /opt/redis-1.02/redis.conf'
    sudo 'ln -s /opt/applications/monk_push/current/config/redis/redis.conf /opt/redis-1.02/redis.conf'
  end

  desc "Generate static CSS"
  task :sass, :roles => :app do
    run "cd #{release_path} && env RACK_ENV=#{fetch :rack_env} ./vendor/thor/bin/thor monk:sass"
  end
end
