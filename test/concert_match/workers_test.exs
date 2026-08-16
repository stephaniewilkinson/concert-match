defmodule ConcertMatch.WorkersTest do
  use ConcertMatch.DataCase, async: true
  use Oban.Testing, repo: ConcertMatch.Repo

  import ConcertMatch.AccountsFixtures
  import ConcertMatch.MusicFixtures

  alias ConcertMatch.Music.UserArtist
  alias ConcertMatch.Spotify.Api
  alias ConcertMatch.Spotify.OAuth
  alias ConcertMatch.Workers.RefreshTasteWorker
  alias ConcertMatch.Workers.SweepEventsWorker

  describe "RefreshTasteWorker" do
    test "imports one user's taste" do
      user = user_fixture()

      Req.Test.stub(Api, fn conn ->
        conn = Plug.Conn.fetch_query_params(conn)

        case conn.request_path do
          "/v1/me/top/artists" ->
            Req.Test.json(conn, %{"items" => [spotify_artist("Radiohead")]})

          "/v1/me/following" ->
            Req.Test.json(conn, %{"artists" => %{"items" => [], "cursors" => %{}}})

          _ ->
            Req.Test.json(conn, %{"items" => [], "next" => nil})
        end
      end)

      assert :ok = perform_job(RefreshTasteWorker, %{user_id: user.id})
      assert Repo.aggregate(UserArtist, :count) == 3
    end

    test "cancels rather than retrying when there is no refresh token" do
      user = expired_user_fixture(%{refresh_token: nil})

      # Retrying can't fix this; the user has to log in again. Returning an
      # error would just burn attempts and noise up the dashboard.
      assert {:cancel, :no_refresh_token} = perform_job(RefreshTasteWorker, %{user_id: user.id})
    end

    test "treats a deleted user as done, not failed" do
      assert :ok = perform_job(RefreshTasteWorker, %{user_id: 999_999})
    end

    test "returns an error so Oban retries a transient Spotify failure" do
      user = user_fixture()

      Req.Test.stub(Api, fn conn ->
        conn |> Plug.Conn.put_status(503) |> Req.Test.json(%{"error" => "unavailable"})
      end)

      assert {:error, _} = perform_job(RefreshTasteWorker, %{user_id: user.id})
    end

    test "an empty-args run fans out one job per user" do
      user_fixture()
      user_fixture()

      assert :ok = perform_job(RefreshTasteWorker, %{})

      assert length(all_enqueued(worker: RefreshTasteWorker)) == 2
    end

    test "refreshes an expired token on the way through" do
      user = expired_user_fixture()

      Req.Test.stub(OAuth, fn conn ->
        Req.Test.json(conn, spotify_tokens(%{"access_token" => "fresh"}))
      end)

      Req.Test.stub(Api, fn conn ->
        case conn.request_path do
          "/v1/me/following" ->
            Req.Test.json(conn, %{"artists" => %{"items" => [], "cursors" => %{}}})

          _ ->
            Req.Test.json(conn, %{"items" => [], "next" => nil})
        end
      end)

      assert :ok = perform_job(RefreshTasteWorker, %{user_id: user.id})
    end
  end

  describe "SweepEventsWorker" do
    setup do
      Application.put_env(:concert_match, :event_sources, [ConcertMatch.StubSource])
      on_exit(fn -> Application.delete_env(:concert_match, :event_sources) end)
      :ok
    end

    test "ingests events for one area" do
      artist_fixture(name: "Radiohead")
      ConcertMatch.StubSource.put_events([source_event(artist_names: ["Radiohead"])])

      assert :ok =
               perform_job(SweepEventsWorker, %{
                 lat: 45.5231,
                 lng: -122.6765,
                 radius_miles: 50
               })

      assert Repo.aggregate(ConcertMatch.Events.Event, :count) == 1
    end

    test "queues a digest when a sweep turns up a shared show" do
      artist = artist_fixture(name: "Radiohead")
      user = user_fixture()
      friend = user_fixture()
      taste_fixture(user, artist, rank: 1)
      taste_fixture(friend, artist, rank: 1)

      ConcertMatch.StubSource.put_events([source_event(artist_names: ["Radiohead"])])

      assert :ok =
               perform_job(SweepEventsWorker, %{lat: 45.5, lng: -122.6, radius_miles: 50})

      assert length(all_enqueued(worker: ConcertMatch.Workers.DigestWorker)) == 2
    end

    test "a sweep that finds nothing shared queues no mail" do
      artist = artist_fixture(name: "Radiohead")
      user = user_fixture()
      taste_fixture(user, artist, rank: 1)

      ConcertMatch.StubSource.put_events([source_event(artist_names: ["Radiohead"])])

      assert :ok =
               perform_job(SweepEventsWorker, %{lat: 45.5, lng: -122.6, radius_miles: 50})

      # No news is no email. That is the point.
      assert all_enqueued(worker: ConcertMatch.Workers.DigestWorker) == []
    end

    test "re-sweeping the same shows queues nothing the second time" do
      artist = artist_fixture(name: "Radiohead")
      user = user_fixture()
      friend = user_fixture()
      taste_fixture(user, artist, rank: 1)
      taste_fixture(friend, artist, rank: 1)

      events = [source_event(source_event_id: "same", artist_names: ["Radiohead"])]
      ConcertMatch.StubSource.put_events(events)

      perform_job(SweepEventsWorker, %{lat: 45.5, lng: -122.6, radius_miles: 50})
      first_count = length(all_enqueued(worker: ConcertMatch.Workers.DigestWorker))

      ConcertMatch.StubSource.put_events(events)
      perform_job(SweepEventsWorker, %{lat: 45.5, lng: -122.6, radius_miles: 50})

      # Only genuinely new shows trigger mail; a show is new once.
      assert length(all_enqueued(worker: ConcertMatch.Workers.DigestWorker)) == first_count
    end

    test "returns an error so Oban retries a failed sweep" do
      ConcertMatch.StubSource.put_error(:econnrefused)

      assert {:error, :econnrefused} =
               perform_job(SweepEventsWorker, %{lat: 45.5, lng: -122.6, radius_miles: 50})
    end

    test "an empty-args run fans out one job per distinct area" do
      # Two users in one city, one in another: two sweeps, not three. This is
      # the property that keeps Ticketmaster spend tied to cities, not people.
      user_fixture(%{home_lat: 45.5231, home_lng: -122.6765})
      user_fixture(%{home_lat: 45.5231, home_lng: -122.6765})
      user_fixture(%{home_lat: 40.7128, home_lng: -74.006})

      assert :ok = perform_job(SweepEventsWorker, %{})

      assert length(all_enqueued(worker: SweepEventsWorker)) == 2
    end

    test "fans out nothing when nobody has set a location" do
      user_fixture(%{home_lat: nil, home_lng: nil})

      assert :ok = perform_job(SweepEventsWorker, %{})
      assert all_enqueued(worker: SweepEventsWorker) == []
    end
  end
end
