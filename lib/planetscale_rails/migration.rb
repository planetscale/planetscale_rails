# frozen_string_literal: true

module PlanetscaleRails
  module Migration
    module Current
      # Allows users to set the `keyspace` option in their migration file.
      # If the migration is being run against PlanetScale (i.e. `ENABLE_PSDB` is set), then we prepend the keyspace to the table name.
      #
      # For local MySQL databases, the keyspace is ignored.
      def create_table(table_name, **options)
        if ENV["ENABLE_PSDB"] && options[:keyspace].present?
          table_name = "#{options[:keyspace]}.#{table_name}"
        end
        super(table_name, **options.except(:keyspace))
      end
    end
  end
end
