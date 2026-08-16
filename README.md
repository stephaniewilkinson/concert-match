# Concert Match

Find concerts you and your friends both want to go to, and get an email when
one is announced.

Concert Match reads your Spotify listening — top artists, follows, saved
library — and does the same for a handful of friends. When a newly announced
show near you features an artist that two or more of you care about, everyone
who matches gets a note saying who else is in.

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
May 2025, so this is a real ceiling rather than a setting. Add each friend's
Spotify account to the app's user allowlist in the dashboard. Concert Match is
built for you and up to four other people, and its design leans on that.

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

## Credentials

Nothing secret gets committed. Credentials load from the environment via
`config/runtime.exs`; `.env` is gitignored. The original version of this app
committed its `.env` in the first week and left it tracked in a public repo for
ten years, which is the kind of mistake you only need to make once.
