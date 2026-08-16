defmodule ConcertMatch.Events do
  @moduledoc """
  Concert ingestion and the overlap query the whole app exists for.
  """

  import Ecto.Query, warn: false

  alias ConcertMatch.Accounts
  alias ConcertMatch.Events.Event
  alias ConcertMatch.Music
  alias ConcertMatch.Music.Name
  alias ConcertMatch.Repo

  require Logger

  @doc """
  Sweep one area with every configured source and store what comes back.

  Returns `{:ok, %{seen: n, new: [%Event{}]}}`. The `new` list is what the
  digest is built from — an event is "newly announced" if we hadn't seen it
  before, which is simpler than reading onsale timestamps and stays correct
  when a second source is added.
  """
  @spec sweep_area(Events.Source.area()) :: {:ok, map()} | {:error, term()}
  def sweep_area(area) do
    sources = Application.get_env(:concert_match, :event_sources, [])

    Enum.reduce_while(sources, {:ok, %{seen: 0, new: []}}, fn source, {:ok, acc} ->
      case source.fetch_events(area) do
        {:ok, events} ->
          {:ok, result} = ingest(events)

          {:cont, {:ok, %{seen: acc.seen + result.seen, new: acc.new ++ result.new}}}

        {:error, reason} ->
          Logger.error("#{inspect(source)} sweep failed: #{inspect(reason)}")
          {:halt, {:error, reason}}
      end
    end)
  end

  @doc """
  Store a batch of normalized events, linking each to known artists by name.
  """
  @spec ingest([map()]) :: {:ok, map()}
  def ingest(events) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    lineup_names = events |> Enum.flat_map(& &1.artist_names) |> Enum.uniq()
    artist_ids = Music.artist_ids_by_normalized_name(lineup_names)

    log_unmatched(lineup_names, artist_ids)

    new_events =
      events
      |> Enum.map(&upsert_event(&1, now, artist_ids))
      |> Enum.filter(& &1)

    {:ok, %{seen: length(events), new: new_events}}
  end

  # Returns the event if it was new to us, nil if we already had it.
  defp upsert_event(attrs, now, artist_ids) do
    existing = Repo.get_by(Event, source: attrs.source, source_event_id: attrs.source_event_id)

    changeset_attrs = attrs |> Map.drop([:artist_names]) |> Map.put(:first_seen_at, now)

    event =
      case existing do
        nil ->
          %Event{}
          |> Event.changeset(changeset_attrs)
          |> Repo.insert!()

        event ->
          # Details drift -- venues change, times get announced. Keep
          # first_seen_at so a rescheduled show isn't re-reported as new.
          event
          |> Event.changeset(Map.put(changeset_attrs, :first_seen_at, event.first_seen_at))
          |> Repo.update!()
      end

    link_artists(event, attrs.artist_names, artist_ids)

    if is_nil(existing), do: event, else: nil
  end

  defp link_artists(event, artist_names, artist_ids) do
    rows =
      artist_names
      |> Enum.flat_map(fn name -> Map.get(artist_ids, Name.normalize(name), []) end)
      |> Enum.uniq()
      |> Enum.map(&%{event_id: event.id, artist_id: &1})

    if rows != [] do
      Repo.insert_all("event_artists", rows, on_conflict: :nothing)
    end
  end

  # Every unmatched name is either an artist nobody here listens to (fine, the
  # overwhelming majority) or a normalization gap (worth fixing). Logging them
  # is how the second kind gets found.
  defp log_unmatched(lineup_names, artist_ids) do
    unmatched =
      lineup_names
      |> Enum.reject(&Map.has_key?(artist_ids, Name.normalize(&1)))
      |> Enum.reject(&(Name.normalize(&1) == ""))

    if unmatched != [] do
      Logger.debug(fn ->
        "unmatched lineup entries (#{length(unmatched)}): " <>
          Enum.join(Enum.take(unmatched, 25), ", ")
      end)
    end
  end

  @doc """
  Which users match each of the given events, and how strongly.

  Returns a map of event id to a list of `%{user_id:, score:}`, sorted by score
  descending. An event matches a user if *any* artist on its lineup appears
  anywhere in that user's pool — bare membership, no threshold. Affinity only
  orders the result.
  """
  @spec matches_for_events([Event.t()] | [integer()]) :: %{integer() => [map()]}
  def matches_for_events([]), do: %{}

  def matches_for_events(events) do
    event_ids =
      Enum.map(events, fn
        %Event{id: id} -> id
        id when is_integer(id) -> id
      end)

    scores = Music.affinity_scores()

    from(ea in "event_artists",
      join: ua in "user_artists",
      on: ua.artist_id == ea.artist_id,
      where: ea.event_id in ^event_ids,
      distinct: true,
      select: {ea.event_id, ua.user_id, ua.artist_id}
    )
    |> Repo.all()
    |> Enum.group_by(fn {event_id, _, _} -> event_id end)
    |> Map.new(fn {event_id, rows} ->
      users =
        rows
        |> Enum.group_by(
          fn {_, user_id, _} -> user_id end,
          fn {_, _, artist_id} -> artist_id end
        )
        # A lineup can hit several of a user's artists; take their best rather
        # than summing, so a festival bill doesn't outrank a headline show.
        |> Enum.map(fn {user_id, artist_ids} ->
          score =
            artist_ids
            |> Enum.map(&Map.get(scores, {user_id, &1}, 0))
            |> Enum.max(fn -> 0 end)

          %{user_id: user_id, score: score}
        end)
        |> Enum.sort_by(& &1.score, :desc)

      {event_id, users}
    end)
  end

  @doc """
  Shared matches: events where two or more users overlap.

  Returns `[%{event: %Event{}, users: [...], score: total}]` sorted by combined
  score descending. The combined score is the sum across matching users, so a
  show two people love outranks one they both faintly recognize — but the
  faint one is still in the list.
  """
  @spec shared_matches([Event.t()]) :: [map()]
  def shared_matches(events) do
    matches = matches_for_events(events)
    by_id = Map.new(events, &{&1.id, &1})

    matches
    |> Enum.filter(fn {_event_id, users} -> length(users) >= 2 end)
    |> Enum.map(fn {event_id, users} ->
      %{
        event: Map.fetch!(by_id, event_id),
        users: users,
        score: users |> Enum.map(& &1.score) |> Enum.sum()
      }
    end)
    |> Enum.sort_by(& &1.score, :desc)
  end

  @doc """
  Solo matches for one user: upcoming events matching them and nobody else.

  The digest falls back to these when there is nothing shared, because a
  "nobody else is in, but you'd like this" email beats silence.
  """
  @spec solo_matches(integer(), [Event.t()]) :: [map()]
  def solo_matches(user_id, events) do
    matches = matches_for_events(events)
    by_id = Map.new(events, &{&1.id, &1})

    matches
    |> Enum.filter(fn {_event_id, users} ->
      length(users) == 1 and hd(users).user_id == user_id
    end)
    |> Enum.map(fn {event_id, users} ->
      %{event: Map.fetch!(by_id, event_id), users: users, score: hd(users).score}
    end)
    |> Enum.sort_by(& &1.score, :desc)
  end

  @doc """
  Everything upcoming that matches one user, split by whether anyone else is in.

  Used by the home page; the digest has its own version that also excludes
  shows the user has already been emailed about.
  """
  @spec matches_for_user(integer()) :: %{shared: [map()], solo: [map()]}
  def matches_for_user(user_id) do
    events = list_upcoming_events()

    shared =
      events
      |> shared_matches()
      |> Enum.filter(fn %{users: users} -> Enum.any?(users, &(&1.user_id == user_id)) end)

    %{shared: shared, solo: solo_matches(user_id, events)}
  end

  @doc """
  Upcoming events we have already stored, optionally limited to those first
  seen since a given time.
  """
  def list_upcoming_events(opts \\ []) do
    since = Keyword.get(opts, :first_seen_since)
    now = DateTime.utc_now()

    Event
    |> where([e], is_nil(e.starts_at) or e.starts_at >= ^now)
    |> then(fn query ->
      if since, do: where(query, [e], e.first_seen_at >= ^since), else: query
    end)
    |> order_by([e], asc: e.starts_at)
    |> Repo.all()
  end

  def get_event!(id), do: Repo.get!(Event, id)

  @doc """
  Sweep every distinct place the users live.
  """
  def sweep_all_areas do
    Accounts.distinct_search_areas()
    |> Enum.map(&sweep_area/1)
  end
end
