# frozen_string_literal: true

require "English"
require "yaml"
require "pty"
require "colorize"

databases = ActiveRecord::Tasks::DatabaseTasks.setup_initial_database_yaml

def find_git_directory
  return ENV["GIT_DIR"] if ENV["GIT_DIR"] && !ENV["GIT_DIR"].empty?

  # it's not set as an env, so let's try to find it
  current_path = Pathname.new(Dir.pwd)

  until current_path.root?
    git_dir = current_path.join(".git")
    return current_path.to_s if git_dir.exist? # this can be a directory or a file (worktree)

    current_path = current_path.parent
  end

  nil
end

def load_pscale_config
  if File.exist?(".pscale.yml")
    return YAML.load_file(".pscale.yml")
  end

  # otherwise, look for a git root directory and load it from there
  git_dir = find_git_directory
  pscale_yaml_path = File.join(git_dir, ".pscale.yml")
  YAML.load_file(pscale_yaml_path)
end

def puts_deploy_request_instructions
  ps_config = load_pscale_config
  database = ps_config["database"]
  branch = ps_config["branch"]
  org = ps_config["org"]

  puts "Create a deploy request for '#{branch.colorize(:blue)}' by running:\n"
  puts "     pscale deploy-request create #{database} #{branch} --org #{org}\n\n"
end

def kill_pscale_process
  Process.kill("TERM", ENV["PSCALE_PID"].to_i) if ENV["PSCALE_PID"]
end

def delete_password
  password_id = ENV["PSCALE_PASSWORD_ID"]
  return unless password_id

  ps_config = load_pscale_config
  database = ps_config["database"]
  branch = ps_config["branch"]

  command = "pscale password delete #{database} #{branch} #{password_id} #{ENV["SERVICE_TOKEN_CONFIG"]} --force"
  output = `#{command}`

  return if $CHILD_STATUS.success?

  puts "Failed to cleanup credentials used for PlanetScale connection. Password ID: #{password_id}".colorize(:red)
  puts "Command: #{command}"
  puts "Output: #{output}"
end

def db_branch_colorized(database, branch)
  "#{database.colorize(:blue)}/#{branch.colorize(:blue)}"
end

namespace :psdb do
  task check_ci: :environment do
    service_token = ENV["PSCALE_SERVICE_TOKEN"] || ENV["PLANETSCALE_SERVICE_TOKEN"]
    service_token_id = ENV["PSCALE_SERVICE_TOKEN_ID"] || ENV["PLANETSCALE_SERVICE_TOKEN_ID"]
    service_token_available = service_token && service_token_id

    if ENV["CI"]
      unless service_token_available
        missing_vars = []
        missing_vars << "PLANETSCALE_SERVICE_TOKEN" unless service_token
        missing_vars << "PLANETSCALE_SERVICE_TOKEN_ID" unless service_token_id

        raise "Unable to authenticate to PlanetScale. Missing environment variables: #{missing_vars.join(", ")}"
      end

      service_token_config = "--service-token #{service_token} --service-token-id #{service_token_id}"

      ENV["SERVICE_TOKEN_CONFIG"] = service_token_config
    end
  end

  def create_connection_string
    ps_config = load_pscale_config
    database = ps_config["database"]
    branch = ps_config["branch"]

    raise "You must have `pscale` installed on your computer".colorize(:red) unless command?("pscale")
    if branch.blank? || database.blank?
      raise "Could not determine which PlanetScale branch to use from .pscale.yml. Please switch to a branch by using: `pscale branch switch branch-name --database db-name --create --wait`".colorize(:red)
    end

    short_hash = SecureRandom.hex(2)[0, 4]
    password_name = "planetscale-rails-#{short_hash}"
    command = "pscale password create #{database} #{branch} #{password_name} -f json --ttl 10m #{ENV["SERVICE_TOKEN_CONFIG"]}"

    output = `#{command}`

    if $CHILD_STATUS.success?
      response = JSON.parse(output)
      puts "Successfully created credentials for PlanetScale #{db_branch_colorized(database, branch)}"
      host = response["access_host_url"]
      username = response["username"]
      password = response["plain_text"]
      ENV["PSCALE_PASSWORD_ID"] = response["id"]

      adapter = "mysql2"

      if defined?(Trilogy)
        adapter = "trilogy"
      end

      url = "#{adapter}://#{username}:#{password}@#{host}:3306/@primary?ssl_mode=VERIFY_IDENTITY"

      # Check common CA paths for certs.
      ssl_ca_path = %w[/etc/ssl/certs/ca-certificates.crt /etc/pki/tls/certs/ca-bundle.crt /etc/ssl/ca-bundle.pem /etc/ssl/cert.pem].find { |f| File.exist?(f) }

      if ssl_ca_path
        url += "&sslca=#{ssl_ca_path}"
      end

      url
    else
      puts "Failed to create credentials for PlanetScale #{db_branch_colorized(database, branch)}"
      puts "Command: #{command}"
      puts "Output: #{output}"
      puts "Please verify that you have the correct permissions to create a password for this branch."
      exit 1
    end
  end

  desc "Create credentials for PlanetScale and sets them to ENV['PSCALE_DATABASE_URL']"
  task "create_creds" => %i[environment check_ci] do
    ENV["PSCALE_DATABASE_URL"] = create_connection_string
    ENV["DISABLE_SCHEMA_DUMP"] = "true"
    ENV["ENABLE_PSDB"] = "true"
  end

  desc "Connects to the current PlanetScale branch and runs rails db:migrate"
  task migrate: %i[environment check_ci create_creds] do
    db_configs = ActiveRecord::Base.configurations.configs_for(env_name: ActiveRecord::Tasks::DatabaseTasks.env)

    unless db_configs.size == 1
      raise "Found multiple database configurations, please specify which database you want to migrate using `psdb:migrate:<database_name>`".colorize(:red)
    end

    puts "Running migrations..."

    command = "DATABASE_URL=\"#{ENV["PSCALE_DATABASE_URL"]}\" bundle exec rails db:migrate"
    IO.popen(command) do |io|
      io.each_line do |line|
        puts line
      end
    end

    if $CHILD_STATUS.success?
      puts_deploy_request_instructions
    else
      puts "Failed to run migrations".colorize(:red)
    end
  ensure
    delete_password
  end

  namespace :migrate do
    ActiveRecord::Tasks::DatabaseTasks.for_each(databases) do |name|
      desc "Connects to the current PlanetScale branch and runs rails db:migrate:#{name}"
      task name => %i[environment check_ci create_creds] do
        puts "Running migrations..."

        name_env_key = "#{name.upcase}_DATABASE_URL"
        command = "#{name_env_key}=\"#{ENV["PSCALE_DATABASE_URL"]}\" bundle exec rails db:migrate:#{name}"

        IO.popen(command) do |io|
          io.each_line do |line|
            puts line
          end
        end

        if $CHILD_STATUS.success?
          puts_deploy_request_instructions
        else
          puts "Failed to run migrations".colorize(:red)
        end
      ensure
        delete_password
      end
    end
  end

  namespace :schema do
    desc "Connects to the current PlanetScale branch and runs rails db:schema:load"
    task load: %i[environment check_ci create_creds] do
      db_configs = ActiveRecord::Base.configurations.configs_for(env_name: ActiveRecord::Tasks::DatabaseTasks.env)

      unless db_configs.size == 1
        raise "Found multiple database configurations, please specify which database you want to load schema for using `psdb:schema:load:<database_name>`".colorize(:red)
      end

      puts "Loading schema..."

      command = "DATABASE_URL=\"#{ENV["PSCALE_DATABASE_URL"]}\" bundle exec rails db:schema:load"
      IO.popen(command) do |io|
        io.each_line do |line|
          puts line
        end
      end

      unless $CHILD_STATUS.success?
        puts "Failed to load schema".colorize(:red)
      end
    ensure
      delete_password
    end

    namespace :load do
      ActiveRecord::Tasks::DatabaseTasks.for_each(databases) do |name|
        desc "Connects to the current PlanetScale branch and runs rails db:schema:load:#{name}"
        task name => %i[environment check_ci create_creds] do
          puts "Loading schema..."

          name_env_key = "#{name.upcase}_DATABASE_URL"
          command = "#{name_env_key}=\"#{ENV["PSCALE_DATABASE_URL"]}\" bundle exec rake db:schema:load:#{name}"

          IO.popen(command) do |io|
            io.each_line do |line|
              puts line
            end
          end

          unless $CHILD_STATUS.success?
            puts "Failed to load schema".colorize(:red)
          end
        ensure
          delete_password
        end
      end
    end
  end

  desc "Connects to the current PlanetScale branch and runs rails db:rollback"
  task rollback: %i[environment check_ci create_creds] do
    db_configs = ActiveRecord::Base.configurations.configs_for(env_name: ActiveRecord::Tasks::DatabaseTasks.env)

    unless db_configs.size == 1
      raise "Found multiple database configurations, please specify which database you want to rollback using `psdb:rollback:<database_name>`".colorize(:red)
    end

    command = "DATABASE_URL=\"#{ENV["PSCALE_DATABASE_URL"]}\" bundle exec rails db:rollback"

    IO.popen(command) do |io|
      io.each_line do |line|
        puts line
      end
    end

    unless $CHILD_STATUS.success?
      puts "Failed to rollback migrations".colorize(:red)
    end
  ensure
    delete_password
  end

  namespace :rollback do
    ActiveRecord::Tasks::DatabaseTasks.for_each(databases) do |name|
      desc "Connects to the current PlanetScale branch and runs rails db:rollback:#{name}"
      task name => %i[environment check_ci create_creds] do
        required_version = Gem::Version.new("6.1.0.0")
        rails_version = Gem::Version.new(Rails.version)

        if rails_version < required_version
          raise "This version of Rails does not support rollback commands for multi-database Rails apps. Please upgrade to at least Rails 6.1"
        end

        puts "Rolling back migrations..."

        name_env_key = "#{name.upcase}_DATABASE_URL"
        command = "#{name_env_key}=\"#{ENV["PSCALE_DATABASE_URL"]}\" bundle exec rake db:rollback:#{name}"

        IO.popen(command) do |io|
          io.each_line do |line|
            puts line
          end
        end

        unless $CHILD_STATUS.success?
          puts "Failed to rollback migrations".colorize(:red)
        end
      ensure
        delete_password
      end
    end
  end
end

def command?(name)
  `which #{name}`
  $CHILD_STATUS.success?
end
