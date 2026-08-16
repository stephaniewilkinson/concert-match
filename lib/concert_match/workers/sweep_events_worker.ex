defmodule ConcertMatch.Workers.SweepEventsWorker do
  @moduledoc """
  Pulls upcoming music events for one area and records which are new.

  Scheduled per distinct user location rather than per artist. With five users
  in one to three cities that is a handful of API calls a night against a
  5000/day quota, regardless of how many thousands of artists are in the pool.
  """

  use Oban.Worker, queue: :events, max_attempts: 3

  alias ConcertMatch.Accounts
  alias ConcertMatch.Events

  require Logger

  # Cron inserts this with no args, which fans out one job per distinct area.
  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) when map_size(args) == 0 do
    enqueue_all()
    :ok
  end

  def perform(%Oban.Job{args: %{"lat" => lat, "lng" => lng, "radius_miles" => radius}}) do
    area = %{lat: lat, lng: lng, radius_miles: radius}

    case Events.sweep_area(area) do
      {:ok, %{seen: seen, new: new}} ->
        Logger.info("swept #{lat},#{lng} r=#{radius}: #{seen} events, #{length(new)} new")

        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Enqueue a sweep for every distinct place the users live.
  """
  def enqueue_all do
    Accounts.distinct_search_areas()
    |> Enum.map(fn area ->
      %{lat: area.lat, lng: area.lng, radius_miles: area.radius_miles}
      |> new()
      |> Oban.insert()
    end)
  end
end
