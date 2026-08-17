defmodule ConcertMatch.MusicTest do
  use ConcertMatch.DataCase, async: true

  import ConcertMatch.AccountsFixtures
  import ConcertMatch.MusicFixtures

  alias ConcertMatch.Music
  alias ConcertMatch.Music.Artist
  alias ConcertMatch.Music.UserArtist
  alias ConcertMatch.Spotify.Api

  # One stub covering every taste endpoint the refresh touches. A request to
  # /me/following would raise here, which is the point: nothing should ask for
  # follows any more.
  defp stub_spotify(opts) do
    top = Keyword.get(opts, :top, %{})
    tracks = Keyword.get(opts, :tracks, [])
    albums = Keyword.get(opts, :albums, [])

    Req.Test.stub(Api, fn conn ->
      conn = Plug.Conn.fetch_query_params(conn)

      case conn.request_path do
        "/v1/me/top/artists" ->
          range = conn.query_params["time_range"]
          Req.Test.json(conn, %{"items" => Map.get(top, range, [])})

        "/v1/me/tracks" ->
          Req.Test.json(conn, %{"items" => tracks, "next" => nil})

        "/v1/me/albums" ->
          Req.Test.json(conn, %{"items" => albums, "next" => nil})
      end
    end)
  end

  defp saved_track(name), do: %{"track" => %{"artists" => [spotify_artist(name)]}}
  defp saved_album(name), do: %{"album" => %{"artists" => [spotify_artist(name)]}}

  describe "refresh_taste/1" do
    test "stores top artists from all three time ranges" do
      user = user_fixture()

      stub_spotify(
        top: %{
          "short_term" => [spotify_artist("Recent Obsession")],
          "medium_term" => [spotify_artist("Steady Favourite")],
          "long_term" => [spotify_artist("Old Reliable")]
        }
      )

      assert {:ok, count} = Music.refresh_taste(user)
      assert count == 3

      sources = Repo.all(from ua in UserArtist, select: ua.source)
      assert Enum.sort(sources) == ["top_long", "top_medium", "top_short"]
    end

    test "stores library artists alongside top artists" do
      user = user_fixture()

      stub_spotify(
        top: %{"long_term" => [spotify_artist("Top Artist")]},
        tracks: [saved_track("Track Artist")],
        albums: [saved_album("Album Artist")]
      )

      assert {:ok, 3} = Music.refresh_taste(user)

      sources = Repo.all(from ua in UserArtist, select: ua.source)
      assert Enum.sort(sources) == ["library", "library", "top_long"]
    end

    # Following is a cheap, often years-stale gesture -- nobody unfollows a
    # band -- so it said much less about turning up to a gig than listening
    # does. Not fetched, and the scope isn't requested either.
    test "never asks Spotify who you follow" do
      user = user_fixture()
      test_pid = self()

      Req.Test.stub(Api, fn conn ->
        send(test_pid, {:path, conn.request_path})
        conn = Plug.Conn.fetch_query_params(conn)

        case conn.request_path do
          "/v1/me/top/artists" -> Req.Test.json(conn, %{"items" => []})
          _ -> Req.Test.json(conn, %{"items" => [], "next" => nil})
        end
      end)

      {:ok, _} = Music.refresh_taste(user)

      refute_received {:path, "/v1/me/following"}
    end

    test "one artist reached by several routes gets a row per route" do
      user = user_fixture()
      artist = spotify_artist("Ubiquitous")

      stub_spotify(
        top: %{"short_term" => [artist], "long_term" => [artist]},
        tracks: [%{"track" => %{"artists" => [artist]}}]
      )

      assert {:ok, 3} = Music.refresh_taste(user)

      # Three reasons to believe, one artist. Keeping them apart is what lets
      # a library presence survive an artist dropping out of the top 250.
      assert Repo.aggregate(Artist, :count) == 1
      assert Repo.aggregate(UserArtist, :count) == 3
    end

    # Spotify caps limit at 50, so anything deeper has to be paged. A stub that
    # answers every request with the same page would let a broken pager pass,
    # so this one serves real slices and asserts the offsets requested.
    test "pages 250 deep through each time range" do
      user = user_fixture()
      catalogue = for i <- 1..250, do: spotify_artist("Ranked #{i}")
      test_pid = self()

      Req.Test.stub(Api, fn conn ->
        conn = Plug.Conn.fetch_query_params(conn)

        case conn.request_path do
          "/v1/me/top/artists" ->
            offset = String.to_integer(conn.query_params["offset"] || "0")
            limit = String.to_integer(conn.query_params["limit"])
            send(test_pid, {:page, conn.query_params["time_range"], offset, limit})

            items = Enum.slice(catalogue, offset, limit)
            next = if offset + limit < length(catalogue), do: "http://next", else: nil

            Req.Test.json(conn, %{"items" => items, "next" => next, "total" => 250})

          _ ->
            Req.Test.json(conn, %{"items" => [], "next" => nil})
        end
      end)

      assert {:ok, count} = Music.refresh_taste(user)

      # 250 per window, and the same catalogue in all three, so one row per
      # artist per window.
      assert count == 750

      # Five pages of 50 for each of the three windows.
      for range <- ~w(short_term medium_term long_term),
          offset <- [0, 50, 100, 150, 200] do
        assert_received {:page, ^range, ^offset, 50}
      end
    end

    test "keeps rank ordering across page boundaries" do
      user = user_fixture()
      catalogue = for i <- 1..120, do: spotify_artist("Ranked #{i}")

      Req.Test.stub(Api, fn conn ->
        conn = Plug.Conn.fetch_query_params(conn)

        case conn.request_path do
          "/v1/me/top/artists" ->
            if conn.query_params["time_range"] == "long_term" do
              offset = String.to_integer(conn.query_params["offset"] || "0")
              limit = String.to_integer(conn.query_params["limit"])
              items = Enum.slice(catalogue, offset, limit)
              next = if offset + limit < length(catalogue), do: "http://next", else: nil
              Req.Test.json(conn, %{"items" => items, "next" => next})
            else
              Req.Test.json(conn, %{"items" => [], "next" => nil})
            end

          _ ->
            Req.Test.json(conn, %{"items" => [], "next" => nil})
        end
      end)

      {:ok, _} = Music.refresh_taste(user)

      ranks =
        Repo.all(
          from ua in UserArtist,
            join: a in Artist,
            on: a.id == ua.artist_id,
            where: ua.rank in [1, 50, 51, 120],
            select: {a.name, ua.rank}
        )
        |> Map.new(fn {name, rank} -> {rank, name} end)

      # Rank has to keep counting across the page seam rather than restarting.
      assert ranks[1] == "Ranked 1"
      assert ranks[50] == "Ranked 50"
      assert ranks[51] == "Ranked 51"
      assert ranks[120] == "Ranked 120"
    end

    test "takes fewer than 250 when that's all Spotify has" do
      user = user_fixture()

      stub_spotify(top: %{"long_term" => for(i <- 1..12, do: spotify_artist("Small #{i}"))})

      # A new account, or a short window, simply has less. Not an error.
      assert {:ok, 12} = Music.refresh_taste(user)
    end

    test "records rank in list order" do
      user = user_fixture()

      stub_spotify(
        top: %{
          "long_term" => [
            spotify_artist("First"),
            spotify_artist("Second"),
            spotify_artist("Third")
          ]
        }
      )

      {:ok, _} = Music.refresh_taste(user)

      ranks =
        Repo.all(
          from ua in UserArtist,
            join: a in Artist,
            on: a.id == ua.artist_id,
            order_by: ua.rank,
            select: {a.name, ua.rank}
        )

      assert ranks == [{"First", 1}, {"Second", 2}, {"Third", 3}]
    end

    test "a second refresh drops artists that fell out of the pool" do
      user = user_fixture()

      stub_spotify(top: %{"long_term" => [spotify_artist("Phase")]})
      {:ok, 1} = Music.refresh_taste(user)

      stub_spotify(top: %{"long_term" => [spotify_artist("Different Phase")]})
      {:ok, 1} = Music.refresh_taste(user)

      names =
        Repo.all(
          from ua in UserArtist,
            join: a in Artist,
            on: a.id == ua.artist_id,
            select: a.name
        )

      assert names == ["Different Phase"]
    end

    test "one user's refresh leaves another user's pool alone" do
      mine = user_fixture()
      yours = user_fixture()

      stub_spotify(top: %{"long_term" => [spotify_artist("Yours")]})
      {:ok, 1} = Music.refresh_taste(yours)

      stub_spotify(top: %{"long_term" => [spotify_artist("Mine")]})
      {:ok, 1} = Music.refresh_taste(mine)

      assert Repo.aggregate(UserArtist, :count) == 2
    end

    test "normalizes artist names on the way in" do
      user = user_fixture()
      stub_spotify(top: %{"long_term" => [spotify_artist("Sigur Rós")]})

      {:ok, _} = Music.refresh_taste(user)

      assert %Artist{normalized_name: "sigur ros"} = Repo.one(Artist)
    end

    # Every other test here uses a handful of artists, which is why the
    # original write survived them: it inserted artists one at a time, and a
    # few round trips are quick anywhere. A real library is hundreds, and
    # against a database on another host that ran past Ecto's 15-second
    # transaction default and left the job retrying from scratch.
    test "writes a realistically large library in a bounded number of queries" do
      user = user_fixture()
      artists = for i <- 1..689, do: spotify_artist("Library Artist #{i}")

      stub_spotify(
        top: %{"long_term" => Enum.take(artists, 50)},
        tracks: Enum.map(Enum.slice(artists, 50, 639), &%{"track" => %{"artists" => [&1]}})
      )

      {:ok, agent} = Agent.start_link(fn -> 0 end)
      test_pid = self()

      # Telemetry handlers are global and run in whichever process emitted the
      # event, so without this filter the count picks up every other async
      # test's queries and the assertion is a coin flip.
      handler = fn _event, _measure, _meta, _config ->
        if self() == test_pid, do: Agent.update(agent, &(&1 + 1))
      end

      :telemetry.attach(
        "query-count-#{inspect(self())}",
        [:concert_match, :repo, :query],
        handler,
        nil
      )

      on_exit(fn -> :telemetry.detach("query-count-#{inspect(self())}") end)

      assert {:ok, count} = Music.refresh_taste(user)
      assert count == 689

      queries = Agent.get(agent, & &1)

      # Batched, this is a couple of statements plus the delete and the pool
      # insert. Per-artist, it was 689 on its own.
      assert queries < 50,
             "expected a bounded number of queries, got #{queries} for 689 artists"
    end

    test "handles an artist appearing many times without a conflict error" do
      user = user_fixture()
      repeated = spotify_artist("Ubiquitous")

      # Postgres refuses an ON CONFLICT DO UPDATE that touches one row twice in
      # a single statement, so batching only works if duplicates are removed
      # before the insert rather than left to the conflict target.
      stub_spotify(
        top: %{
          "short_term" => [repeated],
          "medium_term" => [repeated],
          "long_term" => [repeated]
        },
        tracks: [%{"track" => %{"artists" => [repeated]}}]
      )

      assert {:ok, 4} = Music.refresh_taste(user)
      assert Repo.aggregate(Artist, :count) == 1
    end

    test "a Spotify failure aborts rather than narrowing the pool" do
      user = user_fixture()

      Req.Test.stub(Api, fn conn ->
        conn |> Plug.Conn.put_status(500) |> Req.Test.json(%{"error" => "server_error"})
      end)

      assert {:error, {:http_error, 500, _}} = Music.refresh_taste(user)

      # A partial write here would silently shrink someone's matches.
      assert Repo.aggregate(UserArtist, :count) == 0
    end

    test "refreshes an expired token before calling the API" do
      user = expired_user_fixture()

      Req.Test.stub(ConcertMatch.Spotify.OAuth, fn conn ->
        Req.Test.json(conn, spotify_tokens(%{"access_token" => "fresh"}))
      end)

      stub_spotify(top: %{"long_term" => [spotify_artist("Anything")]})

      assert {:ok, 1} = Music.refresh_taste(user)
    end
  end

  describe "affinity_for_user/1" do
    setup do
      %{user: user_fixture(), artist: artist_fixture(name: "Radiohead")}
    end

    test "scores a #1 artist at the top of the scale", ctx do
      taste_fixture(ctx.user, ctx.artist, source: "top_long", rank: 1)
      assert %{} = scores = Music.affinity_for_user(ctx.user)
      assert scores[ctx.artist.id] == 250
    end

    test "scores the last ranked artist at 1", ctx do
      taste_fixture(ctx.user, ctx.artist, source: "top_long", rank: 250)
      assert Music.affinity_for_user(ctx.user)[ctx.artist.id] == 1
    end

    test "uses the best rank across time ranges rather than summing", ctx do
      taste_fixture(ctx.user, ctx.artist, source: "top_short", rank: 40)
      taste_fixture(ctx.user, ctx.artist, source: "top_long", rank: 2)

      # An artist in all three lists is not three times as loved.
      assert Music.affinity_for_user(ctx.user)[ctx.artist.id] == 249
    end

    test "adds the library weight on top of a rank", ctx do
      taste_fixture(ctx.user, ctx.artist, source: "top_long", rank: 1)
      taste_fixture(ctx.user, ctx.artist, source: "library", rank: nil)

      assert Music.affinity_for_user(ctx.user)[ctx.artist.id] == 250 + 25
    end

    test "scores library presence lowest, but above nothing", ctx do
      taste_fixture(ctx.user, ctx.artist, source: "library", rank: nil)
      assert Music.affinity_for_user(ctx.user)[ctx.artist.id] == 25
    end

    test "ranks a listened-to artist above a library-only one", ctx do
      other = artist_fixture(name: "One Saved Track")
      taste_fixture(ctx.user, ctx.artist, source: "top_long", rank: 200)
      taste_fixture(ctx.user, other, source: "library", rank: nil)

      scores = Music.affinity_for_user(ctx.user)
      assert scores[ctx.artist.id] > scores[other.id]
    end

    test "a genuinely tail-end placement still scores below the library floor", ctx do
      other = artist_fixture(name: "One Saved Track")
      taste_fixture(ctx.user, ctx.artist, source: "top_long", rank: 240)
      taste_fixture(ctx.user, other, source: "library", rank: nil)

      # The bottom tenth of a 250-long list is faint enough that owning a
      # record beats it. Both still match; this only decides the order.
      scores = Music.affinity_for_user(ctx.user)
      assert scores[other.id] > scores[ctx.artist.id]
    end

    test "a followed row left over from an older import scores nothing extra", ctx do
      # The migration clears these, but a row that somehow survived must not
      # quietly keep contributing a weight that no longer exists.
      taste_fixture(ctx.user, ctx.artist, source: "library", rank: nil)

      ConcertMatch.Repo.insert_all("user_artists", [
        %{
          user_id: ctx.user.id,
          artist_id: ctx.artist.id,
          source: "followed",
          rank: nil,
          refreshed_at: DateTime.utc_now() |> DateTime.truncate(:second)
        }
      ])

      assert Music.affinity_for_user(ctx.user)[ctx.artist.id] == 25
    end
  end

  describe "artist_ids_by_normalized_name/1" do
    test "matches across the two catalogues' spellings" do
      artist = artist_fixture(name: "Sigur Rós")

      assert %{"sigur ros" => [id]} =
               Music.artist_ids_by_normalized_name(["Sigur Ros - World Tour"])

      assert id == artist.id
    end

    test "keeps every artist sharing a normalized name" do
      a = artist_fixture(name: "The Beatles")
      b = artist_fixture(name: "Beatles")

      assert %{"beatles" => ids} = Music.artist_ids_by_normalized_name(["Beatles"])
      assert Enum.sort(ids) == Enum.sort([a.id, b.id])
    end

    test "returns nothing for an unknown name" do
      assert Music.artist_ids_by_normalized_name(["Nobody"]) == %{}
    end

    test "ignores names that normalize to nothing" do
      assert Music.artist_ids_by_normalized_name(["!!!", "", nil]) == %{}
    end
  end

  describe "top_artists_for_user/2" do
    test "orders by affinity" do
      user = user_fixture()
      favourite = artist_fixture(name: "Favourite")
      afterthought = artist_fixture(name: "Afterthought")

      taste_fixture(user, favourite, source: "top_long", rank: 1)
      taste_fixture(user, afterthought, source: "library", rank: nil)

      assert [first, second] = Music.top_artists_for_user(user)
      assert first.id == favourite.id
      assert second.id == afterthought.id
    end

    test "respects the limit" do
      user = user_fixture()
      for i <- 1..5, do: taste_fixture(user, artist_fixture(), rank: i)

      assert length(Music.top_artists_for_user(user, 3)) == 3
    end
  end
end
