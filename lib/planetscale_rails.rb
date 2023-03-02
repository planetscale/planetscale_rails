# frozen_string_literal: true

require_relative "planetscale_rails/version"

module PlanetscaleRails
  require "planetscale_rails/railtie" if defined?(Rails)
end
