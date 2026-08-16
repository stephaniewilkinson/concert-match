defmodule ConcertMatch.Notifications do
  @moduledoc """
  Deciding what to tell someone about, and remembering that we told them.
  """

  import Ecto.Query, warn: false

  alias ConcertMatch.Accounts
  alias ConcertMatch.Accounts.User
  alias ConcertMatch.Events
  alias ConcertMatch.Notifications.DigestEmail
  alias ConcertMatch.Notifications.Notification
  alias ConcertMatch.Mailer
  alias ConcertMatch.Repo

  # One email should be worth opening, not a catalogue. Anything trimmed here
  # stays unnotified and simply leads the next night's digest.
  @digest_limit 10

  @doc """
  What to tell this user about, if anything.

  Only shared matches — shows that match this user *and* at least one other
  person — and only ones they haven't already been told about. A show that
  matches you alone is visible on the home page but is not worth an email;
  the premise of the app is going together.

  Ordering is by combined affinity; nothing is filtered out for scoring too
  low. A weak mutual match still gets sent, just further down the list.
  """
  @spec pending_digest(User.t()) :: [map()]
  def pending_digest(%User{} = user) do
    already_told = notified_event_ids(user)

    Events.list_upcoming_events()
    |> Events.shared_matches()
    |> Enum.filter(fn match ->
      involves?(match, user.id) and match.event.id not in already_told
    end)
    |> Enum.take(@digest_limit)
  end

  defp involves?(%{users: users}, user_id), do: Enum.any?(users, &(&1.user_id == user_id))

  @doc """
  Build and send this user's digest, recording what was sent.

  Returns `{:ok, count}` where count is the number of shows mentioned, or
  `{:ok, 0}` when there was nothing to say.
  """
  @spec deliver_digest(User.t()) :: {:ok, non_neg_integer()} | {:error, term()}
  def deliver_digest(%User{notify_enabled: false}), do: {:ok, 0}
  def deliver_digest(%User{email: nil}), do: {:ok, 0}

  def deliver_digest(%User{} = user) do
    case pending_digest(user) do
      [] ->
        {:ok, 0}

      matches ->
        names = display_names(matches)

        with {:ok, _} <- user |> DigestEmail.build(matches, names) |> Mailer.deliver(),
             :ok <- record_sent(user, matches) do
          {:ok, length(matches)}
        end
    end
  end

  @doc """
  Queue digests for everyone affected by a batch of newly discovered events.

  Called by the sweep, so mail is sent because something happened rather than
  because a clock struck. Returns the user ids queued.

  Jobs are inserted per user rather than per event: several new shows found in
  one sweep should produce one email, not five.
  """
  @spec enqueue_for_new_events([Events.Event.t()]) :: [integer()]
  def enqueue_for_new_events([]), do: []

  def enqueue_for_new_events(events) do
    events
    |> Events.shared_matches()
    |> Enum.flat_map(fn %{users: users} -> Enum.map(users, & &1.user_id) end)
    |> Enum.uniq()
    |> Enum.filter(&notifiable?/1)
    |> tap(fn user_ids ->
      Enum.each(user_ids, fn user_id ->
        %{user_id: user_id}
        |> ConcertMatch.Workers.DigestWorker.new()
        |> Oban.insert()
      end)
    end)
  end

  defp notifiable?(user_id) do
    case Accounts.get_user(user_id) do
      %User{notify_enabled: true, email: email} when is_binary(email) -> true
      _ -> false
    end
  end

  # Every other person named in the digest, so the email can say who's in.
  defp display_names(matches) do
    matches
    |> Enum.flat_map(fn %{users: users} -> Enum.map(users, & &1.user_id) end)
    |> Enum.uniq()
    |> then(fn ids -> from(u in User, where: u.id in ^ids, select: {u.id, u.display_name}) end)
    |> Repo.all()
    |> Map.new()
  end

  defp record_sent(user, matches) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    rows =
      Enum.map(matches, fn %{event: event} ->
        %{user_id: user.id, event_id: event.id, sent_at: now}
      end)

    # on_conflict: :nothing rather than an upsert -- if a row already exists we
    # have already told this person, and the timestamp of the first telling is
    # the interesting one.
    Repo.insert_all(Notification, rows, on_conflict: :nothing)
    :ok
  end

  defp notified_event_ids(%User{id: user_id}) do
    Repo.all(from n in Notification, where: n.user_id == ^user_id, select: n.event_id)
  end

  @doc """
  Everyone who should receive a digest tonight.
  """
  def digest_recipients, do: Accounts.notifiable_users()

  def list_notifications(%User{id: user_id}) do
    Repo.all(from n in Notification, where: n.user_id == ^user_id)
  end
end
