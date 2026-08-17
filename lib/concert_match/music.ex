defmodule ConcertMatch.Music do
  @moduledoc """
  Artists, who listens to them, and how much.

  The pool is the top 250 artists in each of Spotify's three time windows, plus
  the artists in your saved library. Matching on bare membership of a short
  list would produce silent weeks, and an app that emails you nothing is an app
  you forget about — so affinity is used only to order results, never to gate
  them.

  Followed artists are deliberately not included. Following on Spotify is a
  cheap, often years-stale gesture, and it turned out to say much less about
  whether someone would turn up to a gig than actually listening does.
  """

  import Ecto.Query, warn: false

  alias ConcertMatch.Accounts
  alias ConcertMatch.Accounts.User
  alias ConcertMatch.Music.Artist
  alias ConcertMatch.Music.Name
  alias ConcertMatch.Music.UserArtist
  alias ConcertMatch.Repo
  alias ConcertMatch.Spotify.Api

  # How deep to read each top-artists window. Spotify pages this 50 at a time,
  # so 250 is five requests per window; fewer come back if that's all the
  # affinity data there is.
  @top_artist_depth 250

  # Affinity weights, derived from the depth so they stay in proportion if it
  # changes again. A ranked artist scores `depth + 1 - rank`, so #1 tops the
  # scale and the last place scores 1. Library presence is the weakest signal
  # there is -- one saved track from 2014 -- but still counts, because it
  # still counts.
  @max_rank @top_artist_depth
  @library_weight div(@top_artist_depth, 10)

  # Ecto's default is 15 seconds. Generous here because the alternative failure
  # mode -- a timeout part way through, then an Oban retry that redoes every
  # Spotify call from scratch -- is far worse than a slow write.
  @write_timeout :timer.minutes(2)

  @time_range_sources %{
    "short_term" => "top_short",
    "medium_term" => "top_medium",
    "long_term" => "top_long"
  }

  @doc """
  Pull everything Spotify will tell us about one user's taste and store it.

  Returns the number of `user_artists` rows written.

  ## Options

    * `:on_progress` — a one-argument function called as each stage starts and
      as library pages arrive. An import crosses five Spotify endpoints and can
      page through thousands of saved tracks, so a caller that shows a spinner
      and nothing else leaves people wondering whether it has hung.

  Progress messages are structured rather than pre-worded, so the wording stays
  in whatever is displaying them.
  """
  @spec refresh_taste(User.t(), keyword()) :: {:ok, non_neg_integer()} | {:error, term()}
  def refresh_taste(%User{} = user, opts \\ []) do
    on_progress = Keyword.get(opts, :on_progress, fn _ -> :ok end)

    with {:ok, token, user} <- Accounts.fresh_access_token(user),
         {:ok, entries} <- collect_taste(token, on_progress) do
      write_taste(user, entries, on_progress)
    end
  end

  # Each source contributes {spotify_artist, source, rank}. Failures on any one
  # source abort the refresh rather than silently narrowing someone's pool.
  defp collect_taste(token, on_progress) do
    with {:ok, top} <- collect_top_artists(token, on_progress),
         on_progress.({:library, 0}),
         {:ok, library} <- Api.library_artists(token, on_progress) do
      {:ok, top ++ Enum.map(library, &{&1, "library", nil})}
    end
  end

  defp collect_top_artists(token, on_progress) do
    Enum.reduce_while(@time_range_sources, {:ok, []}, fn {time_range, source}, {:ok, acc} ->
      on_progress.({:top_artists, time_range})

      case Api.top_artists(token, time_range, @top_artist_depth) do
        {:ok, artists} ->
          ranked = artists |> Enum.with_index(1) |> Enum.map(fn {a, i} -> {a, source, i} end)
          {:cont, {:ok, acc ++ ranked}}

        error ->
          {:halt, error}
      end
    end)
  end

  # Postgres caps a statement at 65535 parameters. Artists carry six columns
  # each, so this leaves an order of magnitude of headroom while still cutting
  # a large library down to a couple of statements.
  @insert_chunk_size 1_000

  defp write_taste(user, entries, on_progress) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    on_progress.({:saving, length(entries)})

    # Deliberately outside the transaction below. Artists are a shared
    # catalogue rather than this user's data, so writing them early is
    # harmless if the pool write then fails, and it keeps the transaction
    # short -- which is the whole point of this function's shape.
    artist_ids = upsert_artists(entries, now)

    rows =
      entries
      |> Enum.map(fn {spotify_artist, source, rank} ->
        %{
          user_id: user.id,
          artist_id: Map.fetch!(artist_ids, spotify_artist["id"]),
          source: source,
          rank: rank,
          refreshed_at: now
        }
      end)
      # An artist can be in the library and the top 250 both; one row per
      # (user, artist, source) is the contract the unique index enforces.
      |> Enum.uniq_by(&{&1.user_id, &1.artist_id, &1.source})

    Repo.transaction(
      fn ->
        # Replace the pool wholesale rather than diffing it. An earlier version
        # deleted rows older than this run's timestamp, which quietly did
        # nothing when two refreshes landed inside the same second and left
        # artists in the pool after they'd fallen out of every Spotify source.
        Repo.delete_all(from ua in UserArtist, where: ua.user_id == ^user.id)

        rows
        |> Enum.chunk_every(@insert_chunk_size)
        |> Enum.reduce(0, fn chunk, acc ->
          {count, _} = Repo.insert_all(UserArtist, chunk)
          acc + count
        end)
      end,
      timeout: @write_timeout
    )
  end

  # One statement per thousand artists rather than one per artist.
  #
  # This used to insert them one at a time, which was fine on a laptop and not
  # fine against a database on another host: a 689-artist library meant 689
  # sequential round trips inside a transaction, which at ordinary network
  # latency ran past Ecto's 15-second default and left the job to time out and
  # retry from the beginning, over and over.
  defp upsert_artists(entries, now) do
    entries
    |> Enum.map(fn {spotify_artist, _source, _rank} -> spotify_artist end)
    # Postgres refuses an ON CONFLICT DO UPDATE that would touch the same row
    # twice in one statement, so duplicates have to go before the insert, not
    # be left to the conflict target.
    |> Enum.uniq_by(& &1["id"])
    |> Enum.map(fn artist ->
      name = artist["name"]

      %{
        spotify_id: artist["id"],
        name: name,
        normalized_name: Name.normalize(name),
        image_url: image_url(artist),
        inserted_at: now,
        updated_at: now
      }
    end)
    |> Enum.chunk_every(@insert_chunk_size)
    |> Enum.flat_map(fn chunk ->
      {_count, returned} =
        Repo.insert_all(Artist, chunk,
          on_conflict: {:replace, [:name, :normalized_name, :image_url, :updated_at]},
          conflict_target: :spotify_id,
          returning: [:id, :spotify_id],
          timeout: @write_timeout
        )

      returned
    end)
    |> Map.new(&{&1.spotify_id, &1.id})
  end

  defp image_url(%{"images" => [%{"url" => url} | _]}), do: url
  defp image_url(_), do: nil

  @doc """
  Affinity for every (user, artist) pair, as a map keyed by `{user_id,
  artist_id}`.

  Ranked sources contribute `depth + 1 - rank`; only the best rank across the
  three time ranges counts, so an artist in all three isn't triple-weighted.
  Follows and library presence add their flat weights on top.
  """
  @spec affinity_scores() :: %{{integer(), integer()} => integer()}
  def affinity_scores do
    from(ua in UserArtist, select: {ua.user_id, ua.artist_id, ua.source, ua.rank})
    |> Repo.all()
    |> Enum.group_by(fn {user_id, artist_id, _, _} -> {user_id, artist_id} end)
    |> Map.new(fn {key, rows} -> {key, score_rows(rows)} end)
  end

  @doc """
  Affinity for one user's artists, keyed by artist id.
  """
  @spec affinity_for_user(User.t() | integer()) :: %{integer() => integer()}
  def affinity_for_user(%User{id: id}), do: affinity_for_user(id)

  def affinity_for_user(user_id) when is_integer(user_id) do
    from(ua in UserArtist,
      where: ua.user_id == ^user_id,
      select: {ua.user_id, ua.artist_id, ua.source, ua.rank}
    )
    |> Repo.all()
    |> Enum.group_by(fn {_, artist_id, _, _} -> artist_id end)
    |> Map.new(fn {artist_id, rows} -> {artist_id, score_rows(rows)} end)
  end

  defp score_rows(rows) do
    best_rank =
      rows
      |> Enum.filter(fn {_, _, _, rank} -> is_integer(rank) end)
      |> Enum.map(fn {_, _, _, rank} -> rank end)
      |> Enum.min(fn -> nil end)

    sources = MapSet.new(rows, fn {_, _, source, _} -> source end)

    rank_score = if best_rank, do: @max_rank + 1 - best_rank, else: 0
    library_score = if MapSet.member?(sources, "library"), do: @library_weight, else: 0

    rank_score + library_score
  end

  @doc """
  Look up artists by normalized name, for matching event lineups.

  Returns a map of normalized name to artist id. One name can legitimately map
  to several Spotify artists, so this keeps them all.
  """
  @spec artist_ids_by_normalized_name([String.t()]) :: %{String.t() => [integer()]}
  def artist_ids_by_normalized_name(names) do
    normalized = names |> Enum.map(&Name.normalize/1) |> Enum.reject(&(&1 == "")) |> Enum.uniq()

    from(a in Artist,
      where: a.normalized_name in ^normalized,
      select: {a.normalized_name, a.id}
    )
    |> Repo.all()
    |> Enum.group_by(fn {name, _} -> name end, fn {_, id} -> id end)
  end

  def list_artists, do: Repo.all(Artist)

  def get_artist_by_spotify_id(spotify_id), do: Repo.get_by(Artist, spotify_id: spotify_id)

  @doc """
  A user's artists ordered by affinity, for display.
  """
  def top_artists_for_user(%User{id: user_id}, limit \\ 50) do
    scores = affinity_for_user(user_id)
    ids = scores |> Map.keys()

    from(a in Artist, where: a.id in ^ids)
    |> Repo.all()
    |> Enum.sort_by(&Map.get(scores, &1.id, 0), :desc)
    |> Enum.take(limit)
  end
end
