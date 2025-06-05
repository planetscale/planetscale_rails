## GitHub Actions example

To automate branch creation and running migrations, you can setup a branch and run `rails psdb:migrate` from GitHub Actions.

Here is a full example workflow that:
1. Creates a branch matching the git branch name.
2. Runs rails migrations.
3. Opens a deploy request if any migrations were run.
4. Comments on the pull request with the diff + link to the deploy request.

### Migrate schema workflow

This workflow will run on any pull request that is opened with a change to `db/schema.rb`.

Secrets needed to be set:
- `PLANETSCALE_ORG_NAME`
- `PLANETSCALE_DATABASE_NAME`
- `PLANETSCALE_SERVICE_TOKEN_ID`
- `PLANETSCALE_SERVICE_TOKEN`

The PlanetScale service token must have the `connect_branch`, `create_branch`, `delete_branch_password`, `read_branch`, `create_deploy_request`, and `read_deploy_request` permissions on the database.

```yaml
name: Run database migrations
on: 
  pull_request:
    branches: [ main ]
    paths:
      - 'db/schema.rb'

jobs:
  planetscale:
    permissions: 
      pull-requests: write
      contents: read

    runs-on: ubuntu-latest
    steps:
      - name: checkout
        uses: actions/checkout@v3
      - name: Create a branch
        uses: planetscale/create-branch-action@v4
        id: create_branch
        with:
          org_name: ${{ secrets.PLANETSCALE_ORG_NAME }}
          database_name: ${{ secrets.PLANETSCALE_DATABASE_NAME }}
          branch_name: ${{ github.head_ref }}
          from: main
          check_exists: true
          wait: true
        env:
          PLANETSCALE_SERVICE_TOKEN_ID: ${{ secrets.PLANETSCALE_SERVICE_TOKEN_ID }}
          PLANETSCALE_SERVICE_TOKEN: ${{ secrets.PLANETSCALE_SERVICE_TOKEN }}
      - uses: actions/checkout@v3
      - name: Set up Ruby
        uses: ruby/setup-ruby@v1
        with:
          ruby-version: 3.2.1
      - name: Cache Ruby gems
        uses: actions/cache@v3
        with:
          path: vendor/bundle
          key: ${{ runner.os }}-gems-${{ hashFiles('**/Gemfile.lock') }}
          restore-keys: |
            ${{ runner.os }}-gems-
      - name: Install dependencies
        run: |
          bundle config --local path vendor/bundle
          bundle config --local deployment true
          bundle install
      - name: Set migration config
        run: |
          echo "org: ${{ secrets.PLANETSCALE_ORG_NAME }}" > .pscale.yml
          echo "database: ${{ secrets.PLANETSCALE_DATABASE_NAME }}" >> .pscale.yml
          echo "branch: ${{ github.head_ref }}" >> .pscale.yml
      - name: Setup pscale
        uses: planetscale/setup-pscale-action@v1
      - name: Run migrations
        run: |
          bundle exec rails psdb:migrate > migration-output.txt
        env:
          PLANETSCALE_SERVICE_TOKEN_ID: ${{ secrets.PLANETSCALE_SERVICE_TOKEN_ID }}
          PLANETSCALE_SERVICE_TOKEN: ${{ secrets.PLANETSCALE_SERVICE_TOKEN }}
      - name: Open DR if migrations
        run: |
          if grep -q "migrated" migration-output.txt; then
            echo "DB_MIGRATED=true" >> $GITHUB_ENV
            if pscale deploy-request create ${{ secrets.PLANETSCALE_DATABASE_NAME }} ${{ github.head_ref }}; then
              cat migration-output.txt
              echo "DR_OPENED=true" >> $GITHUB_ENV
              echo "Deploy request successfully opened"
            else
              echo "Error: Deployment request failed"
              exit 0
            fi
          else
            echo "Did not open a DR since nothing found in migration-output.txt"
            cat migration-output.txt
            exit 0
          fi
        env:
          PLANETSCALE_SERVICE_TOKEN_ID: ${{ secrets.PLANETSCALE_SERVICE_TOKEN_ID }}
          PLANETSCALE_SERVICE_TOKEN: ${{ secrets.PLANETSCALE_SERVICE_TOKEN }}
      - name: Get Deploy Requests
        if: ${{ env.DR_OPENED }}
        env:
          PLANETSCALE_SERVICE_TOKEN_ID: ${{ secrets.PLANETSCALE_SERVICE_TOKEN_ID }}
          PLANETSCALE_SERVICE_TOKEN: ${{ secrets.PLANETSCALE_SERVICE_TOKEN }}
        run: |
          deploy_request_number=$(pscale deploy-request show ${{ secrets.PLANETSCALE_DATABASE_NAME }} ${{ github.head_ref }} -f json | jq -r '.number')
          echo "DEPLOY_REQUEST_NUMBER=$deploy_request_number" >> $GITHUB_ENV
      - name: Comment PR - db migrated
        if: ${{ env.DR_OPENED }}
        env:
          PLANETSCALE_SERVICE_TOKEN_ID: ${{ secrets.PLANETSCALE_SERVICE_TOKEN_ID }}
          PLANETSCALE_SERVICE_TOKEN: ${{ secrets.PLANETSCALE_SERVICE_TOKEN }}
        run: |
          sleep 2
          echo "Deploy request opened: https://app.planetscale.com/${{ secrets.PLANETSCALE_ORG_NAME }}/${{ secrets.PLANETSCALE_DATABASE_NAME }}/deploy-requests/${{ env.DEPLOY_REQUEST_NUMBER }}" >> migration-message.txt
          echo "" >> migration-message.txt
          echo "\`\`\`diff" >> migration-message.txt
          pscale deploy-request diff ${{ secrets.PLANETSCALE_DATABASE_NAME }} ${{ env.DEPLOY_REQUEST_NUMBER }}  -f json | jq -r '.[].raw' >> migration-message.txt
          echo "\`\`\`" >> migration-message.txt
      - name: Comment PR - db migrated
        uses: thollander/actions-comment-pull-request@v2
        if: ${{ env.DR_OPENED }}
        with:
          filePath: migration-message.txt
```
