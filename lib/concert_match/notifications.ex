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
  What to send this user, if anything.

  Returns `%{shared: [...], solo: [...]}`. `shared` is the point of the app —
  shows that match this user and at least one other person. `solo` is the
  fallback used only when there is nothing shared, because a "nobody else is
  in, but you'd like this" email beats silence.

  Ordering is by combined affinity; nothing is filtered out for scoring too
  low. A weak mutual match still gets sent, just further down the list.
  """
  @spec pending_digest(User.t()) :: %{shared: [map()], solo: [map()]}
  def pending_digest(%User{} = user) do
    events = Events.list_upcoming_events()
    already_told = notified_event_ids(user)

    shared =
      events
      |> Events.shared_matches()
      |> Enum.filter(fn match ->
        involves?(match, user.id) and match.event.id not in already_told
      end)
      |> Enum.take(@digest_limit)

    solo =
      if shared == [] do
        user.id
        |> Events.solo_matches(events)
        |> Enum.reject(&(&1.event.id in already_told))
        |> Enum.take(@digest_limit)
      else
        []
      end

    %{shared: shared, solo: solo}
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
    digest = pending_digest(user)
    matches = digest.shared ++ digest.solo

    if matches == [] do
      {:ok, 0}
    else
      names = display_names(matches)

      with {:ok, _} <- user |> DigestEmail.build(digest, names) |> Mailer.deliver(),
           :ok <- record_sent(user, matches) do
        {:ok, length(matches)}
      end
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
