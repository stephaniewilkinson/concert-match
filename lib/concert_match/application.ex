defmodule ConcertMatch.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
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
end
