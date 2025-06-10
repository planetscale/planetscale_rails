# frozen_string_literal: true

module PlanetscaleRails
  module Migration
    module Current
      # Allows users to set the `keyspace` option in their migration file or via an ENV var PLANETSCALE_DEFAULT_KEYSPACE.
      # If the migration is being run against PlanetScale (i.e. `ENABLE_PSDB` is set), then we prepend the keyspace to the table name.
      #
      # For local MySQL databases, the keyspace is ignored.
      def create_table(table_name, **options)
        keyspace = options[:keyspace] || ENV["PLANETSCALE_DEFAULT_KEYSPACE"]
        if ENV["ENABLE_PSDB"] && keyspace.present?
          table_name = "#{keyspace}.#{table_name}"
        end
        super(table_name, **options.except(:keyspace))
      end
    end
  end
end
