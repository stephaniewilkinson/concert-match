import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :concert_match, ConcertMatch.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "concert_match_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :concert_match, ConcertMatchWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "Ipj1X8XWbklf7KiN9jXgMVyZVzybi5QUQB6AlD4aO8hToodjT+xm8hQeBcYgz5vK",
  server: false

# In test we don't send emails
config :concert_match, ConcertMatch.Mailer, adapter: Swoosh.Adapters.Test

# Jobs run inline via Oban.Testing rather than through queues or cron
config :concert_match, Oban, testing: :manual

# Credentials are dummies; every outbound call is stubbed with Req.Test.
config :concert_match, :spotify,
  client_id: "test-client-id",
  client_secret: "test-client-secret",
  redirect_uri: "http://127.0.0.1:4002/auth/spotify/callback"

config :concert_match, :ticketmaster, api_key: "test-api-key"

config :concert_match, :spotify_req_options,
  plug: {Req.Test, ConcertMatch.Spotify.OAuth},
  retry: false

config :concert_match, :ticketmaster_req_options,
  plug: {Req.Test, ConcertMatch.Events.Sources.Ticketmaster},
  retry: false

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
