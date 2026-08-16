defmodule ConcertMatch.Workers.DigestWorker do
  @moduledoc """
  Sends one user their digest of newly announced shared shows.

  Queued by `SweepEventsWorker` when a sweep actually turns something up, not
  on a schedule — no news means no mail. One job per user rather than per
  event, so a sweep that finds four matching shows sends one email listing
  four, not four emails.

  Running it with empty args fans out to everyone with something pending,
  which is useful by hand but is not wired to cron.
  """

  use Oban.Worker, queue: :mailers, max_attempts: 3

  alias ConcertMatch.Accounts
  alias ConcertMatch.Notifications

  require Logger

  # Cron inserts this with no args, fanning out one job per recipient.
  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) when map_size(args) == 0 do
    enqueue_all()
    :ok
  end

  def perform(%Oban.Job{args: %{"user_id" => user_id}}) do
    case Accounts.get_user(user_id) do
      nil ->
        :ok

      user ->
        case Notifications.deliver_digest(user) do
          {:ok, 0} ->
            :ok

          {:ok, count} ->
            Logger.info("sent digest to user #{user_id}: #{count} shows")
            :ok

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  @doc """
  Enqueue a digest for everyone who wants one.
  """
  def enqueue_all do
    Notifications.digest_recipients()
    |> Enum.map(&(%{user_id: &1.id} |> new() |> Oban.insert()))
  end
end
