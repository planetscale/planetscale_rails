# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "planetscale_rails"
require "minitest/autorun"
require "minitest/pride"
require "stringio"

# Add present? method to simulate Rails behavior
class Object
  def present?
    !blank?
  end

  def blank?
    respond_to?(:empty?) ? empty? : !self
  end
end

class NilClass
  def blank?
    true
  end
end

class String
  def blank?
    strip.empty?
  end
end

# Add except method to Hash to simulate Rails behavior
class Hash
  def except(*keys)
    dup.tap do |hash|
      keys.each { |key| hash.delete(key) }
    end
  end
end

# Base class that simulates Rails Migration
class BaseMigration
  def create_table(table_name, **options)
    # This is the "original" create_table method that would be in Rails
    @last_table_name = table_name
    @last_options = options
  end
end

# Helper class to simulate Rails migration behavior
class MockMigration < BaseMigration
  include PlanetscaleRails::Migration::Current

  attr_reader :last_table_name, :last_options
end

# Helper method to capture stdout
def capture_stdout
  original_stdout = $stdout
  $stdout = StringIO.new
  yield
  output = $stdout.string
  $stdout = original_stdout
  output
end
