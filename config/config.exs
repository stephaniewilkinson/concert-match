# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :concert_match,
  ecto_repos: [ConcertMatch.Repo],
  generators: [timestamp_type: :utc_datetime]

# Configure the endpoint
config :concert_match, ConcertMatchWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: ConcertMatchWeb.ErrorHTML, json: ConcertMatchWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: ConcertMatch.PubSub,
  live_view: [signing_salt: "xxDjSGZZ"]

# Configure the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :concert_match, ConcertMatch.Mailer, adapter: Swoosh.Adapters.Local

# Background jobs. Queues are sized for a handful of users, not a crowd.
#
# The nightly chain is separated in time rather than chained by callback:
# taste first, then the event sweep, then digests. An hour of slack between
# stages is far more than five users need, and it means a stalled refresh
# delays one night's email rather than wedging the pipeline.
config :concert_match, Oban,
  repo: ConcertMatch.Repo,
  queues: [default: 5, spotify: 2, events: 2, mailers: 5],
  plugins: [
    {Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 7},
    {Oban.Plugins.Cron,
     crontab: [
       # Times are UTC. 09:00 UTC is the small hours across the US.
       {"0 9 * * *", ConcertMatch.Workers.RefreshTasteWorker},
       {"0 10 * * *", ConcertMatch.Workers.SweepEventsWorker},
       {"0 11 * * *", ConcertMatch.Workers.DigestWorker}
     ]}
  ]

# Spotify stays the only OAuth provider. Credentials come from the
# environment -- never commit them; the 2016 app's .env is still in this
# repo's history as a cautionary tale.
config :concert_match, :spotify,
  client_id: nil,
  client_secret: nil,
  redirect_uri: "http://127.0.0.1:4000/auth/spotify/callback"

# Event data. Ticketmaster Discovery is the only source for now; see
# ConcertMatch.Events.Source for the behaviour a second one would implement.
config :concert_match, :ticketmaster, api_key: nil

config :concert_match, :event_sources, [ConcertMatch.Events.Sources.Ticketmaster]

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  concert_match: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.12",
  concert_match: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
