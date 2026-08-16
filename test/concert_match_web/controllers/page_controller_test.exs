defmodule ConcertMatchWeb.PageControllerTest do
  use ConcertMatchWeb.ConnCase, async: true

  import ConcertMatch.AccountsFixtures

  test "the splash invites anonymous visitors to log in", %{conn: conn} do
    html = conn |> get(~p"/") |> html_response(200)

    assert html =~ "Concerts you and your friends both want to see"
    assert html =~ ~p"/auth/spotify"
  end

  test "the splash points logged-in users at their matches", %{conn: conn} do
    user = user_fixture()

    html =
      conn
      |> init_test_session(user_id: user.id)
      |> get(~p"/")
      |> html_response(200)

    assert html =~ "See your matches"
    refute html =~ "Log in with Spotify"
  end
end
