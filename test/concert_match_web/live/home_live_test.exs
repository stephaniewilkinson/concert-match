defmodule ConcertMatchWeb.HomeLiveTest do
  use ConcertMatchWeb.ConnCase, async: true
  use Oban.Testing, repo: ConcertMatch.Repo

  import Phoenix.LiveViewTest
  import ConcertMatch.AccountsFixtures
  import ConcertMatch.MusicFixtures

  alias ConcertMatch.Workers.RefreshTasteWorker

  setup %{conn: conn} do
    user = user_fixture(%{display_name: "Steph"})
    artist = artist_fixture(name: "Radiohead")

    %{
      conn: init_test_session(conn, user_id: user.id),
      user: user,
      artist: artist
    }
  end

  test "prompts for a location when none is set", %{conn: conn, user: user} do
    ConcertMatch.Repo.update!(Ecto.Changeset.change(user, home_lat: nil, home_lng: nil))

    {:ok, _live, html} = live(conn, ~p"/home")

    assert html =~ "Set your location"
  end

  describe "importing music" do
    test "offers a button rather than an incantation", %{conn: conn} do
      {:ok, _live, html} = live(conn, ~p"/home")

      assert html =~ "Import your listening"
      assert html =~ "Import my music"

      # The empty state used to tell people to call an Elixir function, which
      # nobody can do from a browser.
      refute html =~ "refresh_taste"
    end

    test "clicking it queues an import", %{conn: conn, user: user} do
      {:ok, live, _html} = live(conn, ~p"/home")

      html = live |> element("button", "Import my music") |> render_click()

      assert html =~ "Importing"
      assert [job] = all_enqueued(worker: RefreshTasteWorker)
      assert job.args == %{"user_id" => user.id}
    end

    test "clicking twice does not import twice", %{conn: conn} do
      {:ok, live, _html} = live(conn, ~p"/home")

      live |> element("button", "Import my music") |> render_click()
      render_click(live, "import_music", %{})

      assert length(all_enqueued(worker: RefreshTasteWorker)) == 1
    end

    test "shows the import as running after a page reload", %{conn: conn, user: user} do
      {:ok, :queued} = RefreshTasteWorker.enqueue(user.id)

      {:ok, _live, html} = live(conn, ~p"/home")

      # Read from Oban rather than remembered in the socket, so a refresh
      # mid-import doesn't offer a button that would do nothing.
      assert html =~ "Importing"
    end

    test "updates the page when the import finishes", %{conn: conn, user: user, artist: artist} do
      {:ok, live, _html} = live(conn, ~p"/home")

      # Stand in for the worker: taste lands, then it announces itself.
      taste_fixture(user, artist, rank: 1)

      Phoenix.PubSub.broadcast(
        ConcertMatch.PubSub,
        RefreshTasteWorker.topic(user.id),
        {:taste_refreshed, 1}
      )

      html = render(live)
      assert html =~ "Imported 1 artist from Spotify"
      assert html =~ "Radiohead"
      refute html =~ "Import your listening"
    end

    test "reports a failure instead of spinning forever", %{conn: conn, user: user} do
      {:ok, live, _html} = live(conn, ~p"/home")

      live |> element("button", "Import my music") |> render_click()

      Phoenix.PubSub.broadcast(
        ConcertMatch.PubSub,
        RefreshTasteWorker.topic(user.id),
        {:taste_failed, :no_refresh_token}
      )

      html = render(live)
      assert html =~ "log in again"
      assert html =~ "Import my music"
    end
  end

  test "says nothing matches yet once taste exists", %{conn: conn, user: user, artist: artist} do
    taste_fixture(user, artist, rank: 1)

    {:ok, _live, html} = live(conn, ~p"/home")

    assert html =~ "Nothing upcoming matches you yet"
    assert html =~ "Radiohead"
  end

  test "shows a solo match", %{conn: conn, user: user, artist: artist} do
    taste_fixture(user, artist, rank: 1)
    event_fixture(name: "Radiohead at the Crystal") |> lineup_fixture(artist)

    {:ok, _live, html} = live(conn, ~p"/home")

    assert html =~ "Radiohead at the Crystal"
    assert html =~ "Shows for you"
    refute html =~ "into this too"
  end

  test "names the friend on a shared match", %{conn: conn, user: user, artist: artist} do
    friend = user_fixture(%{display_name: "Nate"})
    taste_fixture(user, artist, rank: 1)
    taste_fixture(friend, artist, rank: 1)
    event_fixture(name: "Radiohead at the Crystal") |> lineup_fixture(artist)

    {:ok, _live, html} = live(conn, ~p"/home")

    assert html =~ "You and your friends"
    assert html =~ "Nate is into this too"
    # Never list yourself as the friend who's also going.
    refute html =~ "Steph is into this too"
  end

  test "lists several friends", %{conn: conn, user: user, artist: artist} do
    nate = user_fixture(%{display_name: "Nate"})
    adam = user_fixture(%{display_name: "Adam"})

    for u <- [user, nate, adam], do: taste_fixture(u, artist, rank: 1)
    event_fixture() |> lineup_fixture(artist)

    {:ok, _live, html} = live(conn, ~p"/home")

    assert html =~ "are into this too"
    assert html =~ "Nate"
    assert html =~ "Adam"
  end

  test "orders shared matches by combined affinity", %{conn: conn, user: user, artist: artist} do
    friend = user_fixture(%{display_name: "Nate"})
    beloved = artist_fixture(name: "Beloved")

    taste_fixture(user, artist, source: "library", rank: nil)
    taste_fixture(friend, artist, source: "library", rank: nil)
    taste_fixture(user, beloved, source: "top_long", rank: 1)
    taste_fixture(friend, beloved, source: "top_long", rank: 1)

    event_fixture(name: "Faint Show") |> lineup_fixture(artist)
    event_fixture(name: "Loud Show") |> lineup_fixture(beloved)

    {:ok, _live, html} = live(conn, ~p"/home")

    loud_at = :binary.match(html, "Loud Show") |> elem(0)
    faint_at = :binary.match(html, "Faint Show") |> elem(0)

    # Both present -- ranking, not filtering.
    assert loud_at < faint_at
  end
end
