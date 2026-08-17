defmodule ConcertMatchWeb.SettingsLiveTest do
  use ConcertMatchWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ConcertMatch.AccountsFixtures

  alias ConcertMatch.Accounts

  setup %{conn: conn} do
    user = user_fixture(%{email: "from-spotify@example.com", display_name: "Steph"})
    %{conn: init_test_session(conn, user_id: user.id), user: user}
  end

  describe "email" do
    test "shows the current address", %{conn: conn} do
      {:ok, _live, html} = live(conn, ~p"/settings")

      assert html =~ "from-spotify@example.com"
      assert html =~ "Where to email you"
    end

    test "saves a new address", %{conn: conn, user: user} do
      {:ok, live, _html} = live(conn, ~p"/settings")

      live
      |> form("form", user: %{email: "somewhere-i-read@example.com"})
      |> render_submit()

      assert Accounts.get_user!(user.id).email == "somewhere-i-read@example.com"
    end

    test "rejects an address that isn't one", %{conn: conn, user: user} do
      {:ok, live, _html} = live(conn, ~p"/settings")

      html =
        live
        |> form("form", user: %{email: "nope"})
        |> render_submit()

      assert html =~ "must look like an email"
      assert Accounts.get_user!(user.id).email == "from-spotify@example.com"
    end

    test "won't leave notifications on with no address", %{conn: conn} do
      {:ok, live, _html} = live(conn, ~p"/settings")

      html =
        live
        |> form("form", user: %{email: "", notify_enabled: "true"})
        |> render_submit()

      assert html =~ "is needed to send you concert emails"
    end

    test "validates as you type without saving", %{conn: conn, user: user} do
      {:ok, live, _html} = live(conn, ~p"/settings")

      html =
        live
        |> form("form", user: %{email: "half-typed@"})
        |> render_change()

      assert html =~ "must look like an email"
      assert Accounts.get_user!(user.id).email == "from-spotify@example.com"
    end
  end

  describe "location and radius" do
    test "saves a home location", %{conn: conn, user: user} do
      {:ok, live, _html} = live(conn, ~p"/settings")

      live
      |> form("form", user: %{home_lat: "40.7128", home_lng: "-74.0060", radius_miles: "25"})
      |> render_submit()

      reloaded = Accounts.get_user!(user.id)
      assert_in_delta reloaded.home_lat, 40.7128, 0.0001
      assert_in_delta reloaded.home_lng, -74.006, 0.0001
      assert reloaded.radius_miles == 25
    end

    test "rejects coordinates off the planet", %{conn: conn} do
      {:ok, live, _html} = live(conn, ~p"/settings")

      html =
        live
        |> form("form", user: %{home_lat: "999"})
        |> render_submit()

      assert html =~ "must be less than or equal to 90"
    end

    # Sent by the Geolocate JS hook once the browser resolves coordinates.
    # Uses somewhere far from the fixture's default so a pass can't be the
    # fixture value being mistaken for the hook's.
    test "the geolocation hook fills the form without saving", %{conn: conn, user: user} do
      {:ok, live, _html} = live(conn, ~p"/settings")

      html = render_hook(live, "set_location", %{"lat" => 51.5074, "lng" => -0.1278})

      assert html =~ "51.5074"
      # Filled in, not committed -- the user still has to press Save.
      assert_in_delta Accounts.get_user!(user.id).home_lat, 45.5231, 0.0001
    end
  end

  test "turning notifications off is allowed", %{conn: conn, user: user} do
    {:ok, live, _html} = live(conn, ~p"/settings")

    live
    |> form("form", user: %{notify_enabled: "false"})
    |> render_submit()

    refute Accounts.get_user!(user.id).notify_enabled
  end
end
