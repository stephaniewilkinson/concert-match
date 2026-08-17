# Concert Match

Find concerts you and your friends both want to go to, and get an email when
one is announced.

Concert Match reads your Spotify listening — your top 250 artists in each of
three time windows, everyone you follow, and your saved library — and does the
same for a handful of friends. When a show near you features an artist that two
or more of you care about, everyone who matches gets a note saying who else is
in.

Matching is deliberately wide: any overlap counts. Affinity only decides the
order things appear in, never whether they appear at all.

Mail is sent when there's something to say, not on a schedule. A show that
matches only you appears on the home page but doesn't earn an email; a quiet
week is a silent week.

Originally built in 2016 as a code-school project in Node and Express;
rewritten in Elixir. The 2016 version is still in this repo's history.

## Requirements

- Elixir 1.15+ and Erlang/OTP 26+
- PostgreSQL
- A Spotify app (see below)
- A Ticketmaster Discovery API key

## Setup

```sh
cp .env.example .env      # then fill it in
mix setup                 # deps, database, assets
mix phx.server
```

The app runs at http://127.0.0.1:4000.

### Spotify

Create an app at [developer.spotify.com/dashboard](https://developer.spotify.com/dashboard)
and register `http://127.0.0.1:4000/auth/spotify/callback` as a redirect URI —
Spotify requires the loopback IP rather than `localhost`.

**Spotify caps development-mode apps at 5 authenticated users.** Extended access
has required a registered organization with substantial monthly actives since
May 2025, so this is a real ceiling rather than a setting. Concert Match is
built for you and up to four other people, and its design leans on that.

Adding someone is manual and there is no API for it: Dashboard → your app →
Settings → User Management → Add new user, then their name and the email address
on their Spotify account. Note that a person who *hasn't* been added can still
complete the Spotify login — it's their API calls that come back 403 — so the
app names the cap explicitly when that happens rather than saying "login failed".

A friend can join at any point. When their listening is first imported, shows
already sitting in the database get re-checked, so an overlap on something
announced weeks ago still reaches both of you.

Scopes used: `user-top-read`, `user-follow-read`, `user-library-read`,
`playlist-read-private`, `user-read-email`.

### Ticketmaster

Get a free key at [developer.ticketmaster.com](https://developer.ticketmaster.com).
The free tier allows 5000 calls/day at 5 requests/second, far more than this app
needs — event lookups scale with the number of cities you and your friends live
in, not the number of artists you listen to.

Ticketmaster is currently the only viable free source of concert data.
Bandsintown went partner-only and Songkick now requires a paid license that
explicitly excludes hobby projects. Event ingestion sits behind the
`ConcertMatch.Events.Source` behaviour so a second source can be added without
touching the matching logic.

## Development

```sh
mix test          # test suite
mix precommit     # compile with warnings as errors, format, test
```

Sent mail is viewable in development at http://127.0.0.1:4000/dev/mailbox.

## Deploying

`render.yaml` is a [Render Blueprint](https://render.com/docs/blueprint-spec).
Point Render's **New → Blueprint** flow at this repo and it creates the web
service and a Postgres database together. You'll be prompted for the values
marked `sync: false`: `SECRET_KEY_BASE`, the Spotify and Ticketmaster
credentials, and optionally `RESEND_API_KEY` / `MAIL_FROM`.

Generate the secret yourself:

```sh
mix phx.gen.secret
```

Don't use Render's "generate value" for this one. Its generated secrets are
base64-encoded 256-bit values — 44 characters — and Plug's cookie store
requires at least 64, so the service deploys cleanly and then 500s on the first
request that touches a session. `config/runtime.exs` checks the length at boot
so it fails obviously instead.

Two things to do after the first deploy:

1. **Register the callback URL with Spotify.** The app derives it from
   `RENDER_EXTERNAL_HOSTNAME`, so it will be
   `https://<your-service>.onrender.com/auth/spotify/callback`. It has to be
   added to the Spotify app's redirect URIs verbatim or login fails.
2. **Set up mail.** Without `RESEND_API_KEY` the app runs and matches normally
   but delivers nothing — Swoosh falls back to an in-memory adapter. It logs a
   warning at startup when this is the case, so check the boot log.

Migrations run from the start command rather than `preDeployCommand`, which
Render only offers on paid instance types. That's fine for a single instance;
if this ever runs more than one, move them so concurrent boots can't race.

Note that free web services sleep when idle, and the nightly schedule is Oban
cron *inside* the app — a sleeping service runs no cron and skips that night's
sweep. If that becomes a problem the honest fix is a paid instance.

To build and run a release locally:

```sh
./build.sh
DATABASE_URL=... SECRET_KEY_BASE=$(mix phx.gen.secret) PHX_HOST=localhost \
  _build/release/bin/migrate && _build/release/bin/server
```

## Credentials

Nothing secret gets committed. Credentials load from the environment via
`config/runtime.exs`; `.env` is gitignored. The original version of this app
committed its `.env` in the first week and left it tracked in a public repo for
ten years, which is the kind of mistake you only need to make once.
