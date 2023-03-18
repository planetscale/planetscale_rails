# frozen_string_literal: true

require "English"
require "yaml"
require "pty"
require "colorize"

databases = ActiveRecord::Tasks::DatabaseTasks.setup_initial_database_yaml

def shared_deps(name = nil)
  return [:environment, :check_ci, "setup_pscale:#{name}".to_sym] if name
  return %i[environment check_ci] if name.nil?
end

def puts_deploy_request_instructions
  ps_config = YAML.load_file(".pscale.yml")
  database = ps_config["database"]
  branch = ps_config["branch"]
  org = ps_config["org"]

  puts "Create a deploy request for '#{branch}' by running:\n"
  puts "     pscale deploy-request create #{database} #{branch} --org #{org}\n\n"
end

def kill_pscale_process
  Process.kill("TERM", ENV["PSCALE_PID"].to_i) if ENV["PSCALE_PID"]
end

namespace :psdb do
  task check_ci: :environment do
    use_service_token = ENV["PSCALE_SERVICE_TOKEN"] && ENV["PSCALE_SERVICE_TOKEN_ID"]
    if ENV["CI"]
      raise "For CI, you can only authenticate using service tokens." unless use_service_token

      service_token_config = "--service-token #{ENV["PSCALE_SERVICE_TOKEN"]} --service-token-id #{ENV["PSCALE_SERVICE_TOKEN_ID"]}"

      ENV["SERVICE_TOKEN_CONFIG"] = service_token_config
    end
  end

  desc "Setup a proxy to connect to PlanetScale"
  task "setup_pscale" => shared_deps do
    ENV["ENABLE_PSDB"] = "1"
    ENV["DISABLE_PS_GEM"] = "1"
    ps_config = YAML.load_file(".pscale.yml")
    database = ps_config["database"]
    branch = ps_config["branch"]

    raise "You must have `pscale` installed on your computer".colorize(:red) unless command?("pscale")
    if branch.blank? || database.blank?
      raise "Your branch is not properly setup, please switch to a branch by using the CLI.".colorize(:red)
    end

    r, = PTY.open

    puts "Connecting to PlanetScale..."

    # Spawns the process in the background
    pid = Process.spawn("pscale connect #{database} #{branch} --port 3305 #{ENV["SERVICE_TOKEN_CONFIG"]}", out: r)
    ENV["PSCALE_PID"] = pid.to_s

    out = ""
    start_time = Time.current
    time_elapsed = Time.current - start_time
    sleep(1)
    while out.blank? && time_elapsed < 10.seconds
      PTY.check(pid, true)
      out = r.gets
      time_elapsed = Time.current - start_time
    end

    raise "Timed out waiting for PlanetScale connection to be established".colorize(:red) if time_elapsed > 10.seconds
  ensure
    r&.close
  end

  namespace :setup_pscale do
    ActiveRecord::Tasks::DatabaseTasks.for_each(databases) do |name|
      desc "Setup a proxy to connect to #{name} in PlanetScale"
      task name => shared_deps do
        ENV["ENABLE_PSDB"] = "1"
        ENV["DISABLE_PS_GEM"] = "1"
        ps_config = YAML.load_file(".pscale.yml")
        database = ps_config["database"]
        branch = ps_config["branch"]

        raise "You must have `pscale` installed on your computer" unless command?("pscale")
        if branch.blank? || database.blank?
          raise "Your branch is not properly setup, please switch to a branch by using the CLI."
        end
        raise "Unable to run migrations against the main branch" if branch == "main"

        config = Rails.configuration.database_configuration[Rails.env][name]

        raise "Database #{name} is not configured for the current environment" unless config

        r, = PTY.open

        puts "Connecting to PlanetScale..."

        # Spawns the process in the background
        pid = Process.spawn("pscale connect #{database} #{branch} --port 3305 #{ENV["SERVICE_TOKEN_CONFIG"]}", out: r)
        ENV["PSCALE_PID"] = pid.to_s

        out = ""
        start_time = Time.current
        time_elapsed = Time.current - start_time
        sleep(1)
        while out.blank? && time_elapsed < 10.seconds
          PTY.check(pid, true)
          out = r.gets
          time_elapsed = Time.current - start_time
        end

        raise "Timed out waiting for PlanetScale connection to be established" if time_elapsed > 10.seconds

        # Comment out for now, this messes up when running migrations.
        # Kernel.system("bundle exec rails db:environment:set RAILS_ENV=development")
      ensure
        r&.close
      end
    end
  end

  desc "Migrate the database for current environment"
  task migrate: %i[environment check_ci setup_pscale] do
    db_configs = ActiveRecord::Base.configurations.configs_for(env_name: ActiveRecord::Tasks::DatabaseTasks.env)

    unless db_configs.size == 1
      raise "Found multiple database configurations, please specify which database you want to migrate using `psdb:migrate:<database_name>`".colorize(:red)
    end

    puts "Running migrations..."
    Kernel.system("bundle exec rails db:migrate")
    puts "Finished running migrations\n".colorize(:green)
    puts_deploy_request_instructions
  ensure
    kill_pscale_process
  end

  namespace :migrate do
    ActiveRecord::Tasks::DatabaseTasks.for_each(databases) do |name|
      desc "Migrate #{name} database for current environment"
      task name => shared_deps(name) do
        puts "Running migrations..."
        # We run it using the Kernel.system here because this properly handles
        # when exceptions occur whereas Rake::Task.invoke does not.
        Kernel.system("bundle exec rake db:migrate:#{name}")

        puts "Finished running migrations\n".colorize(:green)
        puts_deploy_request_instructions
      ensure
        kill_pscale_process
      end
    end
  end

  namespace :truncate_all do
    ActiveRecord::Tasks::DatabaseTasks.for_each(databases) do |name|
      desc "Truncate all tables in #{name} database for current environment"
      task name => shared_deps(name) do
        puts "Truncating database..."
        # We run it using the Kernel.system here because this properly handles
        # when exceptions occur whereas Rake::Task.invoke does not.
        Kernel.system("bundle exec rake db:truncate_all")
        puts "Finished truncating database."
      ensure
        kill_pscale_process
      end
    end
  end

  namespace :schema do
    namespace :load do
      ActiveRecord::Tasks::DatabaseTasks.for_each(databases) do |name|
        desc "Load the current schema into the #{name} database"
        task name => shared_deps(name) do
          puts "Loading schema..."
          # We run it using the Kernel.system here because this properly handles
          # when exceptions occur whereas Rake::Task.invoke does not.
          Kernel.system("bundle exec rake db:schema:load:#{name}")
          puts "Finished loading schema."
        ensure
          kill_pscale_process
        end
      end
    end
  end

  namespace :rollback do
    ActiveRecord::Tasks::DatabaseTasks.for_each(databases) do |name|
      desc "Rollback #{name} database for current environment"
      task name => shared_deps(name) do
        puts "Rolling back migrations..."
        # We run it using the Kernel.system here because this properly handles
        # when exceptions occur whereas Rake::Task.invoke does not.
        Kernel.system("bundle exec rake db:rollback:#{name}")
        puts "Finished rolling back migrations.".colorize(:green)
      ensure
        kill_pscale_process
      end
    end
  end
end

def command?(name)
  `which #{name}`
  $CHILD_STATUS.success?
end
