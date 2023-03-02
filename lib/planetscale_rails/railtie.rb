# frozen_string_literal: true

# lib/railtie.rb
require "planetscale_rails"
require "rails"

module PlanetscaleRails
  class Railtie < Rails::Railtie
    railtie_name :planetscale_rails

    rake_tasks do
      path = File.expand_path(__dir__)
      Dir.glob("#{path}/tasks/*.rake").each { |f| load f }
    end
  end
end
