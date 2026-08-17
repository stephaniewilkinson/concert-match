defmodule ConcertMatchWeb.DataLiveTest do
  use ConcertMatchWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ConcertMatch.AccountsFixtures
  import ConcertMatch.MusicFixtures

  setup %{conn: conn} do
    user =
      user_fixture(%{
        display_name: "Steph",
        email: "steph@example.com",
        postal_code: "97214",
        postal_place: "Portland, Oregon",
        country: "us"
      })

    %{conn: init_test_session(conn, user_id: user.id), user: user}
  end

  test "requires a login", %{conn: conn} do
    conn = build_conn() |> get(~p"/data")
    assert redirected_to(conn) == ~p"/"
    _ = conn
  end

  describe "account section" do
    test "shows what we hold about you", %{conn: conn} do
      {:ok, _live, html} = live(conn, ~p"/data")

      assert html =~ "Steph"
      assert html =~ "steph@example.com"
      assert html =~ "97214"
      assert html =~ "Portland, Oregon"
      assert html =~ "50 miles"
    end

    # A page that prints a live Spotify credential is a page that leaks one
    # over somebody's shoulder. Presence and expiry are useful; the value is
    # not.
    test "never prints the tokens themselves", %{conn: conn, user: user} do
      {:ok, _live, html} = live(conn, ~p"/data")

      refute html =~ user.access_token
      refute html =~ user.refresh_token
      assert html =~ "aren&#39;t shown here"
    end
  end

  describe "imported artists" do
    test "says when nothing has been imported", %{conn: conn} do
      {:ok, _live, html} = live(conn, ~p"/data")

      assert html =~ "Nothing yet"
    end

    test "summarises the pool by source", %{conn: conn, user: user} do
      taste_fixture(user, artist_fixture(name: "Radiohead"), source: "top_long", rank: 1)
      taste_fixture(user, artist_fixture(name: "Wilco"), source: "library", rank: nil)

      {:ok, _live, html} = live(conn, ~p"/data")

      assert html =~ "2 artists"
      assert html =~ "Top, last year"
      assert html =~ "Saved library"
    end

    test "lists artists with rank, source and affinity", %{conn: conn, user: user} do
      taste_fixture(user, artist_fixture(name: "Radiohead"), source: "top_long", rank: 3)

      {:ok, _live, html} = live(conn, ~p"/data")

      assert html =~ "Radiohead"
      assert html =~ "#3"
      # 250 + 1 - 3
      assert html =~ "248"
    end

    test "collapses an artist reached several ways into one row", %{conn: conn, user: user} do
      artist = artist_fixture(name: "Ubiquitous")
      taste_fixture(user, artist, source: "top_long", rank: 5)
      taste_fixture(user, artist, source: "library", rank: nil)

      {:ok, _live, html} = live(conn, ~p"/data")

      # Sources are listed alphabetically by their key, so library precedes top.
      assert html =~ "Saved library, Top, last year"
      # 246 from the rank plus the 25 library floor.
      assert html =~ "271"
    end

    test "orders strongest first", %{conn: conn, user: user} do
      taste_fixture(user, artist_fixture(name: "Faint"), source: "library", rank: nil)
      taste_fixture(user, artist_fixture(name: "Beloved"), source: "top_long", rank: 1)

      {:ok, _live, html} = live(conn, ~p"/data")

      assert :binary.match(html, "Beloved") |> elem(0) <
               :binary.match(html, "Faint") |> elem(0)
    end

    test "filters by search", %{conn: conn, user: user} do
      taste_fixture(user, artist_fixture(name: "Radiohead"), rank: 1)
      taste_fixture(user, artist_fixture(name: "Wilco"), rank: 2)

      {:ok, live, _html} = live(conn, ~p"/data")

      html = render_change(live, "filter", %{"search" => "wil", "source" => "all"})

      assert html =~ "Wilco"
      refute html =~ ">Radiohead<"
    end

    test "filters by source", %{conn: conn, user: user} do
      taste_fixture(user, artist_fixture(name: "Listened"), source: "top_long", rank: 1)
      taste_fixture(user, artist_fixture(name: "Owned"), source: "library", rank: nil)

      {:ok, live, _html} = live(conn, ~p"/data")

      html = render_change(live, "filter", %{"search" => "", "source" => "library"})

      assert html =~ "Owned"
      refute html =~ ">Listened<"
    end

    test "paginates a large pool", %{conn: conn, user: user} do
      for i <- 1..150 do
        taste_fixture(user, artist_fixture(name: "Artist #{i}"), rank: i)
      end

      {:ok, live, html} = live(conn, ~p"/data")

      assert html =~ "150 artists shown"
      assert html =~ "Page 1 of 2"

      html = render_click(live, "page", %{"to" => "2"})
      assert html =~ "Page 2 of 2"
    end

    test "only shows this user's artists", %{conn: conn, user: user} do
      someone_else = user_fixture()
      taste_fixture(user, artist_fixture(name: "Mine"), rank: 1)
      taste_fixture(someone_else, artist_fixture(name: "Theirs"), rank: 1)

      {:ok, _live, html} = live(conn, ~p"/data")

      assert html =~ "Mine"
      refute html =~ "Theirs"
    end
  end

  describe "matches and emails" do
    test "counts shared and solo matches", %{conn: conn, user: user} do
      artist = artist_fixture(name: "Radiohead")
      friend = user_fixture(%{display_name: "Nate"})
      taste_fixture(user, artist, rank: 1)
      taste_fixture(friend, artist, rank: 1)
      event_fixture() |> lineup_fixture(artist)

      {:ok, _live, html} = live(conn, ~p"/data")

      assert html =~ "1 shared with a friend"
    end

    test "lists emails already sent", %{conn: conn, user: user} do
      artist = artist_fixture(name: "Radiohead")
      friend = user_fixture()
      taste_fixture(user, artist, rank: 1)
      taste_fixture(friend, artist, rank: 1)
      event_fixture(name: "Radiohead at the Crystal") |> lineup_fixture(artist)

      {:ok, 1} = ConcertMatch.Notifications.deliver_digest(user)

      {:ok, _live, html} = live(conn, ~p"/data")

      assert html =~ "Radiohead at the Crystal"
    end

    test "names who you're matched against", %{conn: conn} do
      user_fixture(%{display_name: "Nate"})

      {:ok, _live, html} = live(conn, ~p"/data")

      assert html =~ "Nate"
      assert html =~ "Spotify allows five people"
    end

    test "says so when nobody else has joined", %{conn: conn} do
      {:ok, _live, html} = live(conn, ~p"/data")

      assert html =~ "Nobody else has logged in yet"
    end
  end
end
