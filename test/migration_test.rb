# frozen_string_literal: true

require_relative "test_helper"

class MigrationTest < Minitest::Test
  def setup
    @migration = MockMigration.new
    # Clear environment variables before each test
    ENV.delete("ENABLE_PSDB")
    ENV.delete("PLANETSCALE_DEFAULT_KEYSPACE")
  end

  def teardown
    # Clean up environment variables after each test
    ENV.delete("ENABLE_PSDB")
    ENV.delete("PLANETSCALE_DEFAULT_KEYSPACE")
  end

  def test_create_table_without_enable_psdb_ignores_keyspace
    table_name = "users"
    options = { keyspace: "test_keyspace", id: :uuid }

    @migration.create_table(table_name, **options)

    # Should pass through original table name without keyspace prefix
    assert_equal "users", @migration.last_table_name
    # Should remove keyspace option before passing to super
    assert_equal({ id: :uuid }, @migration.last_options)
  end

  def test_create_table_with_enable_psdb_but_no_keyspace
    ENV["ENABLE_PSDB"] = "1"
    table_name = "users"
    options = { id: :uuid }

    @migration.create_table(table_name, **options)

    # Should pass through original table name without keyspace prefix
    assert_equal "users", @migration.last_table_name
    assert_equal({ id: :uuid }, @migration.last_options)
  end

  def test_create_table_with_enable_psdb_and_keyspace_option
    ENV["ENABLE_PSDB"] = "1"
    table_name = "users"
    options = { keyspace: "test_keyspace", id: :uuid }

    @migration.create_table(table_name, **options)

    # Should prepend keyspace to table name
    assert_equal "test_keyspace.users", @migration.last_table_name
    # Should remove keyspace option before passing to super
    assert_equal({ id: :uuid }, @migration.last_options)
  end

  def test_create_table_with_enable_psdb_and_env_keyspace
    ENV["ENABLE_PSDB"] = "1"
    ENV["PLANETSCALE_DEFAULT_KEYSPACE"] = "env_keyspace"
    table_name = "users"
    options = { id: :uuid }

    @migration.create_table(table_name, **options)

    # Should prepend env keyspace to table name
    assert_equal "env_keyspace.users", @migration.last_table_name
    assert_equal({ id: :uuid }, @migration.last_options)
  end

  def test_create_table_option_keyspace_takes_precedence_over_env
    ENV["ENABLE_PSDB"] = "1"
    ENV["PLANETSCALE_DEFAULT_KEYSPACE"] = "env_keyspace"
    table_name = "users"
    options = { keyspace: "option_keyspace", id: :uuid }

    @migration.create_table(table_name, **options)

    # Should use option keyspace over env keyspace
    assert_equal "option_keyspace.users", @migration.last_table_name
    assert_equal({ id: :uuid }, @migration.last_options)
  end

  def test_create_table_with_empty_keyspace_option
    ENV["ENABLE_PSDB"] = "1"
    table_name = "users"
    options = { keyspace: "", id: :uuid }

    @migration.create_table(table_name, **options)

    # Empty keyspace should be ignored
    assert_equal "users", @migration.last_table_name
    assert_equal({ id: :uuid }, @migration.last_options)
  end

  def test_create_table_with_nil_keyspace_option_but_env_keyspace_present
    ENV["ENABLE_PSDB"] = "1"
    ENV["PLANETSCALE_DEFAULT_KEYSPACE"] = "env_keyspace"
    table_name = "users"
    options = { keyspace: nil, id: :uuid }

    @migration.create_table(table_name, **options)

    # Should fall back to env keyspace when option is nil
    assert_equal "env_keyspace.users", @migration.last_table_name
    assert_equal({ id: :uuid }, @migration.last_options)
  end
end
