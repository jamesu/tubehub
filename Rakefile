task :environment do
  require 'core'
end

namespace :db do
  desc "Migrate the database"
  task(:migrate => :environment) do
    ActiveRecord::Base.logger = Logger.new(STDOUT)
    ActiveRecord::Migration.verbose = true
    ActiveRecord::Migrator.migrate("db/migrate", ENV['VERSION'] ? ENV['VERSION'].to_i : nil)
  end
end
