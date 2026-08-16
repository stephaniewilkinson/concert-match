defmodule ConcertMatch.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  require Logger

  @impl true
  def start(_type, _args) do
    warn_if_mail_is_going_nowhere()

    children = [
      ConcertMatchWeb.Telemetry,
      ConcertMatch.Repo,
      {DNSCluster, query: Application.get_env(:concert_match, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: ConcertMatch.PubSub},
      {Oban, Application.fetch_env!(:concert_match, Oban)},
      # Start to serve requests, typically the last entry
      ConcertMatchWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: ConcertMatch.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    ConcertMatchWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  # Digests are the point of running this in production, and the failure mode
  # of an unconfigured mailer is silence rather than an error -- Swoosh's local
  # adapter accepts every message and stores it in memory. Say so at boot,
  # where the Logger is running; the same warning in config/runtime.exs would
  # be swallowed, because config is evaluated before Logger starts.
  defp warn_if_mail_is_going_nowhere do
    if Application.get_env(:concert_match, :env) == :prod or
         System.get_env("PHX_SERVER") do
      case Application.get_env(:concert_match, ConcertMatch.Mailer)[:adapter] do
        Swoosh.Adapters.Local ->
          Logger.warning("""
          Mail is not configured, so digest emails will not be delivered.

          Matching still works and matches are still visible in the app, but
          nobody will be told about them. Set RESEND_API_KEY and MAIL_FROM.
          """)

        _ ->
          :ok
      end
    end
  end
end
