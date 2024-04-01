# frozen_string_literal: true

require "active_support"

require_relative "planetscale_rails/version"
require_relative "planetscale_rails/migration"

module PlanetscaleRails
  require "planetscale_rails/railtie" if defined?(Rails)
end

ActiveSupport.on_load(:active_record) do
  ActiveRecord::Migration::Current.prepend(PlanetscaleRails::Migration::Current)
end
