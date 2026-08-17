defmodule ConcertMatch.EventsTest do
  use ConcertMatch.DataCase, async: true

  import ConcertMatch.AccountsFixtures
  import ConcertMatch.MusicFixtures

  alias ConcertMatch.Events
  alias ConcertMatch.Events.Event

  describe "ingest/1" do
    test "stores an event and reports it as new" do
      artist_fixture(name: "Radiohead")

      assert {:ok, %{seen: 1, new: [event]}} =
               Events.ingest([source_event(artist_names: ["Radiohead"])])

      assert event.name == "A Show"
      assert Repo.aggregate(Event, :count) == 1
    end

    test "an event seen a second time is not new" do
      artist_fixture(name: "Radiohead")
      incoming = source_event(source_event_id: "same-id")

      {:ok, %{new: [_]}} = Events.ingest([incoming])
      assert {:ok, %{seen: 1, new: []}} = Events.ingest([incoming])

      assert Repo.aggregate(Event, :count) == 1
    end

    test "re-ingesting updates details but preserves first_seen_at" do
      artist_fixture(name: "Radiohead")
      incoming = source_event(source_event_id: "same-id", venue_name: "Old Venue")

      {:ok, %{new: [first]}} = Events.ingest([incoming])

      {:ok, _} = Events.ingest([%{incoming | venue_name: "New Venue"}])

      reloaded = Repo.get!(Event, first.id)
      assert reloaded.venue_name == "New Venue"

      # A rescheduled or corrected show must not re-trigger notifications.
      assert DateTime.compare(reloaded.first_seen_at, first.first_seen_at) == :eq
    end

    test "links lineup entries to artists through normalized names" do
      artist = artist_fixture(name: "Sigur Rós")

      {:ok, %{new: [_event]}} =
        Events.ingest([source_event(artist_names: ["Sigur Ros - World Tour"])])

      # Spotify spells it with the accent, Ticketmaster without and with a
      # tour suffix. The normalized name is what lets them meet.
      linked = Repo.all(from ea in "event_artists", select: ea.artist_id)
      assert linked == [artist.id]
    end

    test "an unknown lineup entry is stored without a link" do
      {:ok, %{new: [_event]}} =
        Events.ingest([source_event(artist_names: ["Nobody Here Listens To This"])])

      assert Repo.aggregate(Event, :count) == 1
      assert Repo.all(from ea in "event_artists", select: ea.artist_id) == []
    end

    # Ticketmaster URLs carry tracking parameters and run long, as do their
    # image URLs and the billed event names. These columns were varchar(255)
    # until a Spotify token of the same shape broke login in production.
    test "stores a long event name, URL, and image URL" do
      long_url = "https://www.ticketmaster.com/event/" <> String.duplicate("x", 500)
      long_name = String.duplicate("Very Long Billed Show Name ", 20)

      assert {:ok, %{new: [event]}} =
               Events.ingest([
                 source_event(name: long_name, url: long_url, image_url: long_url)
               ])

      reloaded = Repo.get!(Event, event.id)
      assert reloaded.name == long_name
      assert reloaded.url == long_url
      assert reloaded.image_url == long_url
    end

    test "a multi-artist lineup links every artist we know" do
      a = artist_fixture(name: "Wilco")
      b = artist_fixture(name: "Sleater-Kinney")

      {:ok, %{new: [_]}} =
        Events.ingest([
          source_event(artist_names: ["Wilco", "Sleater-Kinney", "Some Opener"])
        ])

      linked = Repo.all(from ea in "event_artists", select: ea.artist_id)
      assert Enum.sort(linked) == Enum.sort([a.id, b.id])
    end
  end

  describe "matches_for_events/1" do
    setup do
      radiohead = artist_fixture(name: "Radiohead")
      event = event_fixture() |> lineup_fixture(radiohead)
      %{artist: radiohead, event: event}
    end

    test "a user matches when the artist is anywhere in their pool", ctx do
      user = user_fixture()
      taste_fixture(user, ctx.artist, source: "library", rank: nil)

      matches = Events.matches_for_events([ctx.event])

      # Library presence is the weakest signal there is, and it still matches.
      assert [%{user_id: user_id}] = matches[ctx.event.id]
      assert user_id == user.id
    end

    test "scores a top-1 artist above a library-only one", ctx do
      loves_them = user_fixture()
      owns_one_track = user_fixture()

      taste_fixture(loves_them, ctx.artist, source: "top_long", rank: 1)
      taste_fixture(owns_one_track, ctx.artist, source: "library", rank: nil)

      assert [first, second] = Events.matches_for_events([ctx.event])[ctx.event.id]

      assert first.user_id == loves_them.id
      assert second.user_id == owns_one_track.id
      assert first.score > second.score
    end

    test "an event nobody listens to has no matches", ctx do
      assert Events.matches_for_events([ctx.event]) == %{}
    end

    test "takes a user's best artist on a multi-artist bill", ctx do
      user = user_fixture()
      favourite = artist_fixture(name: "Favourite")

      lineup_fixture(ctx.event, favourite)
      taste_fixture(user, ctx.artist, source: "library", rank: nil)
      taste_fixture(user, favourite, source: "top_short", rank: 1)

      assert [%{score: score}] = Events.matches_for_events([ctx.event])[ctx.event.id]

      # Best-of rather than sum, so a festival bill of also-rans can't
      # outrank a show by someone's actual favourite band.
      assert score == 250
    end

    test "handles an empty list" do
      assert Events.matches_for_events([]) == %{}
    end
  end

  describe "shared_matches/1" do
    setup do
      artist = artist_fixture(name: "Radiohead")
      event = event_fixture() |> lineup_fixture(artist)
      %{artist: artist, event: event}
    end

    test "a show only one person matches is not shared", ctx do
      user = user_fixture()
      taste_fixture(user, ctx.artist, rank: 1)

      assert Events.shared_matches([ctx.event]) == []
    end

    test "a show two people match is shared", ctx do
      one = user_fixture()
      two = user_fixture()
      taste_fixture(one, ctx.artist, rank: 1)
      taste_fixture(two, ctx.artist, rank: 2)

      assert [%{event: event, users: users, score: score}] = Events.shared_matches([ctx.event])

      assert event.id == ctx.event.id
      assert length(users) == 2
      # Summed across the two people: a #1 and a #2 placement.
      assert score == 250 + 249
    end

    # This is the requirement stated outright: match wide, rank by affinity.
    # A threshold would produce silent weeks, so a weak-but-real overlap has
    # to survive into the results.
    test "a weak overlap at the very bottom of both pools still counts", ctx do
      one = user_fixture()
      two = user_fixture()
      taste_fixture(one, ctx.artist, source: "library", rank: nil)
      taste_fixture(two, ctx.artist, source: "library", rank: nil)

      assert [%{score: score}] = Events.shared_matches([ctx.event])
      assert score > 0
    end

    test "orders a mutual favourite above a mutual afterthought", ctx do
      beloved = artist_fixture(name: "Beloved")
      faint_event = event_fixture() |> lineup_fixture(ctx.artist)
      loud_event = event_fixture() |> lineup_fixture(beloved)

      one = user_fixture()
      two = user_fixture()

      taste_fixture(one, ctx.artist, source: "library", rank: nil)
      taste_fixture(two, ctx.artist, source: "library", rank: nil)
      taste_fixture(one, beloved, source: "top_long", rank: 1)
      taste_fixture(two, beloved, source: "top_long", rank: 2)

      assert [first, second] = Events.shared_matches([faint_event, loud_event])

      assert first.event.id == loud_event.id
      assert second.event.id == faint_event.id

      # Both present. Ordering is the whole job of the score.
      assert first.score > second.score
    end

    test "three people on one show all appear", ctx do
      users = for _ <- 1..3, do: user_fixture()
      for u <- users, do: taste_fixture(u, ctx.artist, rank: 1)

      assert [%{users: matched}] = Events.shared_matches([ctx.event])
      assert length(matched) == 3
    end
  end

  describe "solo_matches/2" do
    setup do
      artist = artist_fixture(name: "Radiohead")
      event = event_fixture() |> lineup_fixture(artist)
      %{artist: artist, event: event}
    end

    test "returns shows matching only this user", ctx do
      user = user_fixture()
      taste_fixture(user, ctx.artist, rank: 1)

      assert [%{event: event}] = Events.solo_matches(user.id, [ctx.event])
      assert event.id == ctx.event.id
    end

    test "excludes shows someone else also matches", ctx do
      user = user_fixture()
      other = user_fixture()
      taste_fixture(user, ctx.artist, rank: 1)
      taste_fixture(other, ctx.artist, rank: 1)

      assert Events.solo_matches(user.id, [ctx.event]) == []
    end

    test "excludes another user's solo shows", ctx do
      user = user_fixture()
      other = user_fixture()
      taste_fixture(other, ctx.artist, rank: 1)

      assert Events.solo_matches(user.id, [ctx.event]) == []
    end
  end

  describe "list_upcoming_events/1" do
    test "excludes shows that have already happened" do
      past = DateTime.utc_now() |> DateTime.add(-7, :day) |> DateTime.truncate(:second)
      event_fixture(starts_at: past)
      upcoming = event_fixture()

      assert [found] = Events.list_upcoming_events()
      assert found.id == upcoming.id
    end

    test "keeps shows with no announced date" do
      event = event_fixture(starts_at: nil)
      assert [found] = Events.list_upcoming_events()
      assert found.id == event.id
    end

    test "filters to events first seen since a cutoff" do
      old_stamp = DateTime.utc_now() |> DateTime.add(-2, :day) |> DateTime.truncate(:second)
      cutoff = DateTime.utc_now() |> DateTime.add(-1, :day)

      event_fixture(first_seen_at: old_stamp)
      fresh = event_fixture()

      assert [found] = Events.list_upcoming_events(first_seen_since: cutoff)
      assert found.id == fresh.id
    end
  end

  describe "sweep_area/1" do
    setup do
      # A stub source standing in for Ticketmaster, so the sweep can be
      # exercised without asserting on anybody's HTTP client.
      Application.put_env(:concert_match, :event_sources, [ConcertMatch.StubSource])
      on_exit(fn -> Application.delete_env(:concert_match, :event_sources) end)
      :ok
    end

    test "ingests what the source returns and reports new events" do
      artist_fixture(name: "Radiohead")

      ConcertMatch.StubSource.put_events([
        source_event(source_event_id: "a", artist_names: ["Radiohead"]),
        source_event(source_event_id: "b", artist_names: ["Radiohead"])
      ])

      assert {:ok, %{seen: 2, new: new}} =
               Events.sweep_area(%{lat: 45.5, lng: -122.6, radius_miles: 50})

      assert length(new) == 2
    end

    test "surfaces a source failure rather than reporting an empty sweep" do
      ConcertMatch.StubSource.put_error(:timeout)

      assert {:error, :timeout} =
               Events.sweep_area(%{lat: 45.5, lng: -122.6, radius_miles: 50})
    end
  end
end
