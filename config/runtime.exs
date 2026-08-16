import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/concert_match start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :concert_match, ConcertMatchWeb.Endpoint, server: true
end

config :concert_match, ConcertMatchWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4000"))]

# External API credentials, in every environment. These are read from the
# environment rather than a committed file on purpose -- see this repo's
# history for why. Use direnv, a shell profile, or your host's secret store.
if config_env() != :test do
  # Render populates RENDER_EXTERNAL_HOSTNAME, so the callback URL doesn't have
  # to be configured twice. Whatever this resolves to must be registered
  # verbatim as a redirect URI on the Spotify app, or the login 400s.
  default_redirect_uri =
    case System.get_env("RENDER_EXTERNAL_HOSTNAME") do
      nil -> "http://127.0.0.1:4000/auth/spotify/callback"
      hostname -> "https://#{hostname}/auth/spotify/callback"
    end

  config :concert_match, :spotify,
    client_id: System.get_env("SPOTIFY_CLIENT_ID"),
    client_secret: System.get_env("SPOTIFY_CLIENT_SECRET"),
    redirect_uri: System.get_env("SPOTIFY_REDIRECT_URI") || default_redirect_uri

  config :concert_match, :ticketmaster, api_key: System.get_env("TICKETMASTER_API_KEY")

  if from = System.get_env("MAIL_FROM") do
    config :concert_match, :mail_from, from
  end
end

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :concert_match, ConcertMatch.Repo,
    # ssl: true,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    # For machines with several cores, consider starting multiple pools of `pool_size`
    # pool_count: 4,
    socket_options: maybe_ipv6

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  # Render supplies RENDER_EXTERNAL_HOSTNAME; PHX_HOST overrides it for a
  # custom domain or another host entirely.
  host =
    System.get_env("PHX_HOST") || System.get_env("RENDER_EXTERNAL_HOSTNAME") ||
      raise """
      No hostname configured.

      Set PHX_HOST, or deploy somewhere that populates RENDER_EXTERNAL_HOSTNAME.
      URLs in digest emails are absolute, so guessing here would send people
      links to the wrong place.
      """

  config :concert_match, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :concert_match, ConcertMatchWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :concert_match, ConcertMatchWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :concert_match, ConcertMatchWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # ## Mail
  #
  # Without RESEND_API_KEY the app still boots and still matches -- it just
  # drops every email into the in-memory local adapter. ConcertMatch.Application
  # warns about that at startup, where the Logger is actually running; a warning
  # from here would be swallowed, since config runs before Logger starts.
  #
  # Swoosh ships adapters for Postmark, Mailgun, SES and others if you'd rather
  # use one of those; the shape is the same.
  if api_key = System.get_env("RESEND_API_KEY") do
    config :concert_match, ConcertMatch.Mailer,
      adapter: Swoosh.Adapters.Resend,
      api_key: api_key

    config :swoosh, :api_client, Swoosh.ApiClient.Req
  end
end
