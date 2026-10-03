# Lokka

> **Note**
> Lokka 1.0.0 has migrated from DataMapper to **ActiveRecord**.
> If you are upgrading from v0.6.0 or earlier, please see the [Migration Guide](https://github.com/lokka/lokka/wiki/Migration-Guide-DataMapper-to-ActiveRecord).

CMS written in Ruby for cloud computing.

## Requirements

- Ruby 3.2 or later
- SQLite

## Features

* Performs in the cloud environment such as Google App Engine and Heroku as well as Windows, Mac, and Linux.
* Designed with reference to WordPress for WordPress users to easily understand.
* Easy installation
* Easy to create a theme for designers.
* A clear plug-in API for Rubyists

## Installation

```sh
$ git clone git://github.com/lokka/lokka.git
$ cd lokka
$ bundle install --without=production:test
$ bundle exec rake db:setup
$ bundle exec rackup
```

View at: http://localhost:9292/

## Deployment

See the [Deployment Guide](https://github.com/lokka/lokka/wiki/Deployment) for production deployment instructions using Kamal.

## Docker (Development)

```sh
$ docker-compose build
$ docker-compose run --rm app bundle exec rake db:setup
$ docker-compose up
```

open http://localhost:9292 on your browser.

## Test

```sh
rake test
```

## How to make a theme

Make a directory for theme in public/theme and you need to create entries.erb and entry.erb at least. (erb and haml are available.)

### Index page

public/theme/example/entries.erb:

```erb
<!DOCTYPE html>
<html>
  <head>
    <title>Example</title>
  </head>
  <body>
    <h1><%= @site.title %></h1>
    <% @entries.each do |entry| %>
      <h2><%= entry.title %></h2>
      <div class="body"><%= entry.body %></div>
    <% end %>
  </body>
</html>
```

### Individual page

public/theme/example/entry.erb:

```erb
<!DOCTYPE html>
<html>
  <head>
    <title>Example</title>
  </head>
  <body>
    <h1><%= @site.title %></h1>
    <h2><%= @entry.title %></h2>
    <div class="body"><%= @entry.body %></div>
  </body>
</html>
```

## How to make a plugin

Lokka Plugin is subset of [Sinatra Extension](http://www.sinatrarb.com/extensions.html). but Lokka had a specific rules of nomenclature.
If you need display "Hello, World" when access to "/hello", Write a following.

public/plugin/lokka-hello/lib/lokka/hello.rb:

```ruby
module Lokka::Hello
  def self.registerd(app)
    app.get '/hello' do
      'hello'
    end
  end
end
```

## Copyright

Copyright (c) 2010 Masaki Komagata. See LICENSE for details.

### Public comment protection and quarantine

Public comment POSTs accept only `name`, `email`, `homepage`, and `body`. The route sets
`entry_id` and status itself: anonymous (including stale/deleted-user sessions) is
`MODERATED`; a valid logged-in user is `APPROVED`. Client-supplied IDs, status,
timestamps and other attributes are ignored. Authorized admin/API status workflows
are unchanged. Plugins must not override status via request parameters; use trusted
server-side logic in an authenticated workflow instead.

Anonymous submissions return HTTP 422 for a narrow, deterministic market-advertising
match: an HTTP(S) URL anywhere in name/homepage/body, together with a case-insensitive,
word-bounded phrase: `torzon`, `darknet market(s)`, `darknet marketplace(s)`,
`dark web market(s)`, `dark market(s)`, `darkmarket(s)`, `darknet drug links`,
`darknet drug store`, or `darknet drugs`. A URL also matches when its exact hostname
or a subdomain belongs to the observed advertising hosts: `darknetmarketworld.com`,
`darknetaccess.com`, `darkmarketsonion.com`, `darkweb-storelist.com`,
`darknet-marketslinks.com`, `darknet-marketspro.com`, `darknetmarketnexus.info`,
`darknetmarketnexus.org`, `darknetmarketnexus.net`, `darknetmarketnexus.us`,
`darknetmarketnexus.com`, `nexus-darknet-market-link.com`, `bestdarknetmarkets.com`,
`darknet-market.org`, `marketsdarknet.com`, `market-darknet.org`, or
`darknetmarketnews.com`.
Lookalike hostnames and these domain names appearing only in URL paths do not match
the host rule. General links, language, moderation status,
and discussion of darknet alone are not signals. The same matcher powers quarantine.
This is a conservative rule, not comprehensive spam detection: advertisements can
evade it, and legitimate linked discussion containing these exact market terms can
match. Review dry-run IDs before applying.

Turnstile is enabled only when both site and secret keys are configured (environment
or plugin options). Deployment of plugin code alone does not establish that it is
enabled; configured keys do not prove a bypass occurred. When enabled, anonymous
comment submissions with missing/blank tokens fail locally before any HTTP request.
Verification requires HTTP 200, valid JSON, `success: true`, and the request hostname.
Open/read/write timeouts are 3/5/5 seconds; network failures fail closed. Market
advertising is rejected independently even after a successful verification. Admin
paths remain protected by login; no reachable admin-prefix bypass was established.

The standalone SQLite command needs the existing `sqlite3` gem, this script, and
`lib/lokka/comment_spam.rb`. It does not boot Lokka, load credentials, migrate, or
connect to production automatically. Supply the actual SQLite file explicitly:

```sh
# Default: read-only dry run; JSON count and at most five ID-only samples.
bundle exec ruby scripts/quarantine_comments.rb --database /path/to/comments.sqlite3

# Explicit apply: create a NEW private backup file before changing status.
bundle exec ruby scripts/quarantine_comments.rb --database /path/to/comments.sqlite3 \
  --apply --backup /private/path/comment-quarantine-20261003.json

# Explicit guarded restore using that backup and the same database path.
bundle exec ruby scripts/quarantine_comments.rb --database /path/to/comments.sqlite3 \
  --restore /private/path/comment-quarantine-20261003.json
```

Apply snapshots matched `MODERATED` rows, then acquires a SQLite `IMMEDIATE` write
lock and rechecks their status and content digests. It writes only eligible rows
to an exclusive 0600 JSON backup marked `pending`, flushes/fsyncs the file and its
directory, and sets those rows to `SPAM` in the same transaction with bound SQL
parameters. After a successful commit, it atomically replaces the pending file with
a fsynced 0600 backup marked `applied`, then fsyncs the directory. It never deletes
rows. Backup contains only ID, original status and content digest, plus format
version, lifecycle state and a database-path digest: no names, email
addresses or bodies. Use a private server-side directory and retain the backup for
restore. Existing backup files are never overwritten; use a new filename for repeat
apply. Output has no full bodies, email addresses, links, or credentials.

Rows whose status or any other column changed after the snapshot are skipped and
never included in the backup, even if another operation marked them `SPAM`. New
rows arriving after the snapshot are outside that apply. Restore requires current
`SPAM` and an unchanged digest, preserving later edits and status changes. Repeat
restore is a no-op; repeat apply has no matches until new matching moderated comments
arrive. Status-only writes leave timestamps intact. Dry run and a later apply take
separate snapshots, so rerun dry run immediately before apply and review the result.
Restore accepts only version 2 `applied` backups; pending, incomplete, and old version
1 backups are rejected. Backup write/fsync failures prevent any database mutation;
update or commit errors roll back the transaction and retain a non-restorable
pending backup. If finalization fails before replacement, or the process crashes
after commit but before replacement, rows can remain quarantined with a pending
backup. Retain it for manual server-side investigation; do not change its state or
automatically restore it. A crash before commit leaves pending metadata and SQLite
rolls back its transaction. If the final directory fsync fails after replacement,
the command reports failure but the `applied` file refers to committed changes;
the replacement may not survive a subsequent machine crash.

Backup must remain at its original format, and the database must be accessed through
the same canonical path for restore. The guard cannot detect an edit later reverted
to exactly the same column values. JSON errors use nonzero exit status; successful
operations report `matched`, `changed`, and `skipped` (dry run reports `samples`).
Apply's `matched` is the fixed snapshot count; restore's is the applied backup row
count. Skipped snapshot rows never become restore candidates.

Quarantine hides comments only in themes that restrict public rendering to approved
comments. A theme iterating all entry comments must be fixed separately before relying
on statuses for public visibility. This command does not repair theme rendering.
