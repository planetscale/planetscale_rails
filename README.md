# PlanetScale Rails

[![Gem Version](https://badge.fury.io/rb/planetscale_rails.svg)](https://badge.fury.io/rb/planetscale_rails)

Rake tasks for easily running Rails migrations against PlanetScale database branches.

For information on how to connect your Rails app to PlanetScale, please [see our guide here](https://planetscale.com/docs/tutorials/connect-rails-app).

## Included rake tasks

The rake tasks allow you to use local MySQL for development. When you're ready to make a schema change, you can create a PlanetScale branch and run migrations
against it. See [usage](#usage) for details.

```
rake psdb:migrate                    # Migrate the database for current environment
rake psdb:rollback                   # Rollback primary database for current environment
rake psdb:schema:load                # Load the current schema into the database
rake psdb:setup_pscale               # Setup a proxy to connect to PlanetScale
```

## Installation

Add this line to your application's Gemfile:

```ruby
group :development do
  gem 'planetscale_rails'
end
```

And then execute in your terminal:

```
bundle install
```

## Usage

First, make sure you have the [`pscale` CLI installed](https://github.com/planetscale/cli#installation). You'll use `pscale` to create a new branch.

1. Run this locally, it will create a new branch off of `main`. The `switch` command will update a `.pscale.yml` file to track 
that this is the branch you want to migrate.

```
pscale branch switch my-new-branch-name --database my-db-name --create
```

**Tip:** In your database settings. Enable "Automatically copy migration data." Select "Rails/Phoenix" as the migration framework. This will auto copy your `schema_migrations` table between branches.

2. Once your branch is ready, you can then use the `psdb` rake task to connect to your branch and run `db:migrate`.

```
bundle exec rails psdb:migrate
```

If you run multiple databases in your Rails app, you can specify the DB name.

```
bundle exec rails psdb:migrate:primary
```

This will connect to the branch that you created, and run migrations against the branch.

If you make a mistake, you can use `bundle exec rails psdb:rollback` to rollback the changes on your PlanetScale branch.

3. Next, you can either open the Deploy Request via the UI. Or the CLI.

Via CLI is:
```
pscale deploy-request create database-name my-new-branch-name
```

4. To get your schema change to production, run the deploy request. Then, once it's complete, you can merge your code changes into your `main` branch in git and deploy your application code.


## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/planetscale/planetscale_rails. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/planetscale/planetscale_rails/blob/main/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [Apache 2.0 License](https://opensource.org/license/apache-2-0/).

## Code of Conduct

Everyone interacting in the PlanetScale Rails project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/planetscale/planetscale_rails/blob/main/CODE_OF_CONDUCT.md).
