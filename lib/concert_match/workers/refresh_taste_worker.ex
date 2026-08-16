defmodule ConcertMatch.Workers.RefreshTasteWorker do
  @moduledoc """
  Re-reads one user's Spotify taste.

  Runs nightly per user. Without a stored refresh token this would be
  impossible — which is why the 2016 app could never have grown a feature
  like the digest.
  """

  use Oban.Worker, queue: :spotify, max_attempts: 3

  alias ConcertMatch.Accounts
  alias ConcertMatch.Music

  require Logger

  # Cron inserts this with no args; that run fans out one job per user rather
  # than doing the work itself, so a single slow account can't stall the rest.
  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) when map_size(args) == 0 do
    enqueue_all()
    :ok
  end

  def perform(%Oban.Job{args: %{"user_id" => user_id}}) do
    case Accounts.get_user(user_id) do
      nil ->
        # The user was deleted between scheduling and running. Not an error.
        :ok

      user ->
        case Music.refresh_taste(user) do
          {:ok, count} ->
            Logger.info("refreshed taste for user #{user_id}: #{count} rows")
            :ok

          {:error, :no_refresh_token} ->
            # Nothing a retry can fix; the user has to log in again.
            Logger.warning("user #{user_id} has no refresh token; skipping")
            {:cancel, :no_refresh_token}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  @doc """
  Enqueue a refresh for every user.
  """
  def enqueue_all do
    Accounts.list_users()
    |> Enum.map(&(%{user_id: &1.id} |> new() |> Oban.insert()))
  end
end
