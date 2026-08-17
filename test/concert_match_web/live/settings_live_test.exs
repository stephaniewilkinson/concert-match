defmodule ConcertMatchWeb.SettingsLiveTest do
  use ConcertMatchWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ConcertMatch.AccountsFixtures

  alias ConcertMatch.Accounts
  alias ConcertMatch.Geocoding.Zippopotam

  setup %{conn: conn} do
    user = user_fixture(%{email: "from-spotify@example.com", display_name: "Steph"})
    %{conn: init_test_session(conn, user_id: user.id), user: user}
  end

  # Zippopotam's real response shape, so the parser is exercised rather than
  # bypassed.
  defp stub_place(name, state, lat, lng) do
    Req.Test.stub(Zippopotam, fn conn ->
      Req.Test.json(conn, %{
        "post code" => "10001",
        "places" => [
          %{
            "place name" => name,
            "state" => state,
            "latitude" => to_string(lat),
            "longitude" => to_string(lng)
          }
        ]
      })
    end)
  end

  defp stub_unknown_postal_code do
    Req.Test.stub(Zippopotam, fn conn ->
      conn |> Plug.Conn.put_status(404) |> Req.Test.json(%{})
    end)
  end

  defp stub_geocoder_down do
    Req.Test.stub(Zippopotam, fn conn ->
      conn |> Plug.Conn.put_status(503) |> Req.Test.json(%{})
    end)
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

  describe "location" do
    test "asks for a ZIP code, not coordinates", %{conn: conn} do
      {:ok, _live, html} = live(conn, ~p"/settings")

      assert html =~ "ZIP code"
      # Nobody knows their own latitude.
      refute html =~ "Latitude"
      refute html =~ "Longitude"
    end

    test "saves a ZIP and geocodes it to coordinates", %{conn: conn, user: user} do
      stub_place("New York", "New York", 40.7128, -74.006)

      {:ok, live, _html} = live(conn, ~p"/settings")

      live
      |> form("form", user: %{postal_code: "10001", radius_miles: "25"})
      |> render_submit()

      reloaded = Accounts.get_user!(user.id)
      assert reloaded.postal_code == "10001"
      assert reloaded.postal_place == "New York, New York"
      assert_in_delta reloaded.home_lat, 40.7128, 0.0001
      assert_in_delta reloaded.home_lng, -74.006, 0.0001
      assert reloaded.radius_miles == 25
    end

    test "names the place it resolved to", %{conn: conn} do
      stub_place("New York", "New York", 40.7128, -74.006)

      {:ok, live, _html} = live(conn, ~p"/settings")

      html = live |> form("form", user: %{postal_code: "10001"}) |> render_submit()

      # A typo that happens to be a real code somewhere else is only visible
      # if the resolved place is shown back.
      assert html =~ "New York, New York"
    end

    test "reports a ZIP that doesn't exist", %{conn: conn, user: user} do
      stub_unknown_postal_code()

      {:ok, live, _html} = live(conn, ~p"/settings")

      html = live |> form("form", user: %{postal_code: "00000"}) |> render_submit()

      assert html =~ "isn&#39;t a postal code we can find"
      assert is_nil(Accounts.get_user!(user.id).postal_code)
    end

    test "distinguishes a broken geocoder from a bad ZIP", %{conn: conn} do
      stub_geocoder_down()

      {:ok, live, _html} = live(conn, ~p"/settings")

      html = live |> form("form", user: %{postal_code: "97214"}) |> render_submit()

      # The service being down is not the user's mistake, so don't tell them
      # their input is wrong.
      assert html =~ "try again in a moment"
      refute html =~ "isn&#39;t a postal code"
    end

    test "uppercases and trims", %{conn: conn, user: user} do
      stub_place("Ottawa", "Ontario", 45.4215, -75.6972)

      {:ok, live, _html} = live(conn, ~p"/settings")

      live |> form("form", user: %{postal_code: "  k1a 0b1 "}) |> render_submit()

      assert Accounts.get_user!(user.id).postal_code == "K1A 0B1"
    end

    test "saving other settings does not re-geocode", %{conn: conn, user: user} do
      stub_place("New York", "New York", 40.7128, -74.006)
      {:ok, live, _html} = live(conn, ~p"/settings")
      live |> form("form", user: %{postal_code: "10001"}) |> render_submit()

      # If an unchanged postal code were re-resolved, this error would surface.
      stub_geocoder_down()
      live |> form("form", user: %{email: "new@example.com"}) |> render_submit()

      reloaded = Accounts.get_user!(user.id)
      assert reloaded.email == "new@example.com"
      assert_in_delta reloaded.home_lat, 40.7128, 0.0001
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
