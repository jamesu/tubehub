task :environment do
  require File.join(File.dirname(__FILE__), 'core')
end

def schema_base
  File.join(File.dirname(__FILE__), 'db', 'schema.rb')
end

def dump_schema
  ActiveRecord::SchemaDumper.ignore_tables = []
  io = StringIO.new
  ActiveRecord::SchemaDumper.dump(ActiveRecord::Base.connection, io)
  File.open(schema_base, 'w') { |f| io.rewind; f.write(io.read) }
end

namespace :db do
  desc "Migrate the database"
  task(:migrate => :environment) do
    ActiveRecord::Migration.verbose = true
    ActiveRecord::Migrator.migrate("db/migrate", ENV['VERSION'] ? ENV['VERSION'].to_i : nil)
    dump_schema
  end
  
  namespace :schema do
    desc "Dump the schema"
    task(:dump => :environment) do
      dump_schema
    end
    
    task(:load => :environment) do
      if File.exist?(schema_base)
        ActiveRecord::Base.logger = Logger.new(STDOUT)
        require schema_base
      end
    end
  end
  
  task(:seed => :environment) do
    require File.join(File.dirname(__FILE__), 'db', 'seed.rb')
  end
end
