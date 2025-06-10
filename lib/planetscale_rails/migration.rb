# frozen_string_literal: true

module PlanetscaleRails
  module Migration
    module Current
      # Allows users to set the `keyspace` option in their migration file or via an ENV var PLANETSCALE_DEFAULT_KEYSPACE.
      # If the migration is being run against PlanetScale (i.e. `ENABLE_PSDB` is set), then we prepend the keyspace to the table name.
      #
      # For local MySQL databases, the keyspace is ignored.
      def create_table(table_name, **options)
        keyspace = options[:keyspace]

        if keyspace.blank? && ENV["PLANETSCALE_DEFAULT_KEYSPACE"].present?
          keyspace = ENV["PLANETSCALE_DEFAULT_KEYSPACE"]
          log_keyspace_usage(keyspace)
        end

        if ENV["ENABLE_PSDB"] && keyspace.present?
          table_name = "#{keyspace}.#{table_name}"
        end
        super(table_name, **options.except(:keyspace))
      end

      private

      def log_keyspace_usage(keyspace)
        message = "Using keyspace '#{keyspace}' from PLANETSCALE_DEFAULT_KEYSPACE environment variable"
        if defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger
          Rails.logger.info(message)
        else
          puts message
        end
      end
    end
  end
end
