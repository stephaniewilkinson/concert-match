defmodule ConcertMatch.MusicTest do
  use ConcertMatch.DataCase, async: true

  import ConcertMatch.AccountsFixtures
  import ConcertMatch.MusicFixtures

  alias ConcertMatch.Music
  alias ConcertMatch.Music.Artist
  alias ConcertMatch.Music.UserArtist
  alias ConcertMatch.Spotify.Api

  # One stub covering every taste endpoint the refresh touches.
  defp stub_spotify(opts) do
    top = Keyword.get(opts, :top, %{})
    followed = Keyword.get(opts, :followed, [])
    tracks = Keyword.get(opts, :tracks, [])
    albums = Keyword.get(opts, :albums, [])

    Req.Test.stub(Api, fn conn ->
      conn = Plug.Conn.fetch_query_params(conn)

      case conn.request_path do
        "/v1/me/top/artists" ->
          range = conn.query_params["time_range"]
          Req.Test.json(conn, %{"items" => Map.get(top, range, [])})

        "/v1/me/following" ->
          Req.Test.json(conn, %{"artists" => %{"items" => followed, "cursors" => %{}}})

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

    test "stores follows and library alongside top artists" do
      user = user_fixture()

      stub_spotify(
        top: %{"long_term" => [spotify_artist("Top Artist")]},
        followed: [spotify_artist("Followed Artist")],
        tracks: [saved_track("Track Artist")],
        albums: [saved_album("Album Artist")]
      )

      assert {:ok, 4} = Music.refresh_taste(user)

      sources = Repo.all(from ua in UserArtist, select: ua.source)
      assert Enum.sort(sources) == ["followed", "library", "library", "top_long"]
    end

    test "one artist reached by several routes gets a row per route" do
      user = user_fixture()
      artist = spotify_artist("Ubiquitous")

      stub_spotify(
        top: %{"short_term" => [artist], "long_term" => [artist]},
        followed: [artist],
        tracks: [%{"track" => %{"artists" => [artist]}}]
      )

      assert {:ok, 4} = Music.refresh_taste(user)

      # Four reasons to believe, one artist. Keeping them apart is what lets
      # a follow survive an artist dropping out of the top 50.
      assert Repo.aggregate(Artist, :count) == 1
      assert Repo.aggregate(UserArtist, :count) == 4
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

    test "scores a #1 artist at 50", ctx do
      taste_fixture(ctx.user, ctx.artist, source: "top_long", rank: 1)
      assert %{} = scores = Music.affinity_for_user(ctx.user)
      assert scores[ctx.artist.id] == 50
    end

    test "scores a #50 artist at 1", ctx do
      taste_fixture(ctx.user, ctx.artist, source: "top_long", rank: 50)
      assert Music.affinity_for_user(ctx.user)[ctx.artist.id] == 1
    end

    test "uses the best rank across time ranges rather than summing", ctx do
      taste_fixture(ctx.user, ctx.artist, source: "top_short", rank: 40)
      taste_fixture(ctx.user, ctx.artist, source: "top_long", rank: 2)

      # An artist in all three lists is not three times as loved.
      assert Music.affinity_for_user(ctx.user)[ctx.artist.id] == 49
    end

    test "adds the follow weight on top of a rank", ctx do
      taste_fixture(ctx.user, ctx.artist, source: "top_long", rank: 1)
      taste_fixture(ctx.user, ctx.artist, source: "followed", rank: nil)

      assert Music.affinity_for_user(ctx.user)[ctx.artist.id] == 76
    end

    test "scores a follow with no ranking", ctx do
      taste_fixture(ctx.user, ctx.artist, source: "followed", rank: nil)
      assert Music.affinity_for_user(ctx.user)[ctx.artist.id] == 26
    end

    test "scores library presence lowest, but above nothing", ctx do
      taste_fixture(ctx.user, ctx.artist, source: "library", rank: nil)
      assert Music.affinity_for_user(ctx.user)[ctx.artist.id] == 5
    end

    test "ranks a deliberate follow above a tail-end top-50 placement", ctx do
      other = artist_fixture(name: "Barely Charted")
      taste_fixture(ctx.user, ctx.artist, source: "followed", rank: nil)
      taste_fixture(ctx.user, other, source: "top_long", rank: 48)

      scores = Music.affinity_for_user(ctx.user)
      assert scores[ctx.artist.id] > scores[other.id]
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
