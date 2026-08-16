defmodule ConcertMatch.MusicFixtures do
  @moduledoc """
  Test fixtures for artists, taste, and events.
  """

  alias ConcertMatch.Events.Event
  alias ConcertMatch.Music.Artist
  alias ConcertMatch.Music.UserArtist
  alias ConcertMatch.Repo

  def artist_fixture(attrs \\ %{}) do
    attrs = Map.new(attrs)
    name = attrs[:name] || "Artist #{System.unique_integer([:positive])}"

    %Artist{}
    |> Artist.changeset(%{
      spotify_id: attrs[:spotify_id] || "artist-#{System.unique_integer([:positive])}",
      name: name,
      image_url: attrs[:image_url]
    })
    |> Repo.insert!()
  end

  @doc """
  Give a user a reason to care about an artist.

  `source` defaults to a long-term top placement at the given rank.
  """
  def taste_fixture(user, artist, attrs \\ %{}) do
    attrs = Map.new(attrs)

    %UserArtist{}
    |> UserArtist.changeset(%{
      user_id: user.id,
      artist_id: artist.id,
      source: attrs[:source] || "top_long",
      rank: Map.get(attrs, :rank, 1),
      refreshed_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
    |> Repo.insert!()
  end

  def event_fixture(attrs \\ %{}) do
    attrs = Map.new(attrs)
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    %Event{}
    |> Event.changeset(%{
      source: attrs[:source] || "ticketmaster",
      source_event_id: attrs[:source_event_id] || "evt-#{System.unique_integer([:positive])}",
      name: attrs[:name] || "A Show",
      starts_at: Map.get(attrs, :starts_at, DateTime.add(now, 30, :day)),
      venue_name: attrs[:venue_name] || "Crystal Ballroom",
      city: attrs[:city] || "Portland",
      lat: attrs[:lat],
      lng: attrs[:lng],
      url: attrs[:url],
      image_url: attrs[:image_url],
      first_seen_at: Map.get(attrs, :first_seen_at, now)
    })
    |> Repo.insert!()
  end

  @doc "Put an artist on an event's lineup."
  def lineup_fixture(event, artist) do
    Repo.insert_all("event_artists", [%{event_id: event.id, artist_id: artist.id}],
      on_conflict: :nothing
    )

    event
  end

  @doc "A normalized event as an `Events.Source` would return it."
  def source_event(attrs \\ %{}) do
    attrs = Map.new(attrs)
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    %{
      source: attrs[:source] || "ticketmaster",
      source_event_id: attrs[:source_event_id] || "evt-#{System.unique_integer([:positive])}",
      name: attrs[:name] || "A Show",
      artist_names: attrs[:artist_names] || ["Radiohead"],
      starts_at: Map.get(attrs, :starts_at, DateTime.add(now, 30, :day)),
      venue_name: attrs[:venue_name] || "Crystal Ballroom",
      city: attrs[:city] || "Portland",
      lat: attrs[:lat] || 45.5231,
      lng: attrs[:lng] || -122.6765,
      url: attrs[:url] || "https://example.com/event",
      image_url: attrs[:image_url]
    }
  end

  @doc "A Spotify artist object."
  def spotify_artist(name, overrides \\ %{}) do
    Map.merge(
      %{
        "id" => "sp-#{:erlang.phash2(name)}",
        "name" => name,
        "images" => [%{"url" => "https://example.com/#{:erlang.phash2(name)}.jpg"}]
      },
      overrides
    )
  end
end
