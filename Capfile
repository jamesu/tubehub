load 'deploy'

$:.unshift(File.expand_path('./lib', ENV['rvm_path'])) # Add RVM's lib directory to the load path.
require "rvm/capistrano"                  # Load RVM's capistrano plugin.
set :rvm_ruby_string, 'ruby-1.9.3'        # Or whatever env you want it to run in.

set :application, "tubehub"
set :user, "app"
set :use_sudo, true

set :scm, :git
set :repository,  "/Users/jamesu/Projects/tubehub/.git" #"git@github.com:jamesu/tubehub.git"
set :deploy_via, :copy #:remote_cache
set :deploy_to, "/srv/app_data/apps/#{application}"

role :app, "cuppaserver"
role :web, "cuppaserver"
role :db,  "cuppaserver", :primary => true

set :runner, "deploy"
default_run_options[:pty] = true

namespace :deploy do
  task :start, :roles => :app do
    sudo "start tubehub"
  end
 
  task :stop, :roles => :app do
    sudo "stop tubehub; true"
  end
 
  task :restart, :roles => :app do
    deploy.stop
    deploy.start
  end

  task :copy_config do
    run "for f in /srv/app_data/apps/#{application}/shared/config/*.yml; do cp $f #{release_path}/config/; done"
  end

  task :update_upstart do
    run "foreman export upstart /srv/app_data/apps/#{application}/shared/init -f #{release_path}/Procfile -a tubehub -u app"
    sudo "cp -r /srv/app_data/apps/#{application}/shared/init/* /etc/init/"
  end

  task :update_bundle do
    run "cd #{release_path} && bundle install --without development test"
  end
end

after "deploy:update_code", "deploy:copy_config", "deploy:update_bundle", "deploy:update_upstart"
