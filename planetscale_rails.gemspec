# frozen_string_literal: true

require_relative "lib/planetscale_rails/version"

Gem::Specification.new do |spec|
  spec.name          = "planetscale_rails"
  spec.version       = PlanetscaleRails::VERSION
  spec.authors       = ["Mike Coutermarsh", "Iheanyi Ekechukwu"]
  spec.email         = ["coutermarsh.mike@gmail.com", "iekechukwu@gmail.com"]

  spec.summary       = "Make Rails migrations easy with PlanetScale"
  spec.description   = "A collection of rake tasks to make managing schema migrations with PlanetScale easy"
  spec.homepage      = "https://github.com/planetscale/planetscale_rails"
  spec.license       = "Apache-2.0"
  spec.required_ruby_version = ">= 3.0.0"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{\A(?:test|spec|features|doc)/}) }
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "colorize", "~> 1.0"
  spec.add_dependency "rails", ">= 6.0", "< 9"
end
