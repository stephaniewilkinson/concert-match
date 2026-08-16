defmodule ConcertMatchWeb.HomeLiveTest do
  use ConcertMatchWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ConcertMatch.AccountsFixtures
  import ConcertMatch.MusicFixtures

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

  test "explains that listening hasn't been imported yet", %{conn: conn} do
    {:ok, _live, html} = live(conn, ~p"/home")

    assert html =~ "hasn&#39;t been imported yet"
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
