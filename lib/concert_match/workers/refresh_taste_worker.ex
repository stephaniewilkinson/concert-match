defmodule ConcertMatch.Workers.RefreshTasteWorker do
  @moduledoc """
  Re-reads one user's Spotify taste.

  Runs nightly per user, and on demand when someone presses the import button.
  Without a stored refresh token this would be impossible — which is why the
  2016 app could never have grown a feature like the digest.

  Broadcasts its outcome so a watching LiveView can update, since an import
  crosses several Spotify endpoints and pages the user's whole saved library;
  it is far too slow to do inside a `handle_event`.
  """

  # Deduplicated across the states where a job hasn't finished yet, so pressing
  # the button twice, or pressing it just as the nightly run fires, doesn't
  # import the same library twice.
  use Oban.Worker,
    queue: :spotify,
    max_attempts: 3,
    unique: [period: 300, states: :incomplete]

  alias ConcertMatch.Accounts
  alias ConcertMatch.Music
  alias ConcertMatch.Notifications

  require Logger

  @doc """
  PubSub topic carrying one user's import progress.
  """
  def topic(user_id), do: "taste:#{user_id}"

  @doc """
  Queue an import for one user.

  Returns `{:ok, :queued}` whether or not this call was the one that created
  the job — a duplicate means an import is already on its way, which from the
  caller's point of view is the same outcome.
  """
  def enqueue(user_id) do
    case %{user_id: user_id} |> new() |> Oban.insert() do
      {:ok, _job} -> {:ok, :queued}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Whether an import for this user is queued or running right now.

  Read from Oban's table rather than tracked in the LiveView, so a page reload
  mid-import still shows the right thing.
  """
  # Same set the uniqueness rule uses, so the button's state and the
  # deduplication can't disagree about whether an import is under way.
  @incomplete_states ~w(available scheduled executing retryable suspended)

  def in_progress?(user_id) do
    import Ecto.Query

    ConcertMatch.Repo.exists?(
      from j in Oban.Job,
        where: j.worker == ^Oban.Worker.to_string(__MODULE__),
        where: j.state in ^@incomplete_states,
        where: fragment("?->>'user_id' = ?", j.args, ^to_string(user_id))
    )
  end

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
        on_progress = fn stage -> broadcast(user_id, {:taste_progress, stage}) end

        case Music.refresh_taste(user, on_progress: on_progress) do
          {:ok, count} ->
            # A new person's first import can turn shows already in the
            # database into shared matches, so re-check rather than waiting
            # for each one to be announced again.
            queued = Notifications.enqueue_pending()

            Logger.info(
              "refreshed taste for user #{user_id}: #{count} rows, " <>
                "#{length(queued)} digests queued"
            )

            broadcast(user_id, {:taste_refreshed, count})
            :ok

          {:error, :no_refresh_token} ->
            # Nothing a retry can fix; the user has to log in again.
            Logger.warning("user #{user_id} has no refresh token; skipping")
            broadcast(user_id, {:taste_failed, :no_refresh_token})
            {:cancel, :no_refresh_token}

          {:error, reason} ->
            Logger.error("taste refresh failed for user #{user_id}: #{inspect(reason)}")
            broadcast(user_id, {:taste_failed, reason})
            {:error, reason}
        end
    end
  end

  @doc """
  Enqueue a refresh for every user.
  """
  def enqueue_all do
    Accounts.list_users() |> Enum.map(&enqueue(&1.id))
  end

  defp broadcast(user_id, message) do
    Phoenix.PubSub.broadcast(ConcertMatch.PubSub, topic(user_id), message)
  end
end
