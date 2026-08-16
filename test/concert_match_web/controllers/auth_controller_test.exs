defmodule ConcertMatchWeb.AuthControllerTest do
  use ConcertMatchWeb.ConnCase, async: true

  import ConcertMatch.AccountsFixtures

  alias ConcertMatch.Accounts.User
  alias ConcertMatch.Repo
  alias ConcertMatch.Spotify.OAuth

  # Routes both legs of the login through one stub: the token exchange hits
  # accounts.spotify.com, the profile lookup hits api.spotify.com.
  defp stub_spotify(opts \\ []) do
    tokens = Keyword.get(opts, :tokens, spotify_tokens())
    profile = Keyword.get(opts, :profile, spotify_profile())
    me_status = Keyword.get(opts, :me_status, 200)

    Req.Test.stub(OAuth, fn conn ->
      case conn.request_path do
        "/api/token" ->
          Req.Test.json(conn, tokens)

        "/v1/me" ->
          conn |> Plug.Conn.put_status(me_status) |> Req.Test.json(profile)
      end
    end)
  end

  describe "GET /auth/spotify" do
    test "redirects to Spotify and remembers the state", %{conn: conn} do
      conn = get(conn, ~p"/auth/spotify")

      assert location = redirected_to(conn, 302)
      assert location =~ "https://accounts.spotify.com/authorize"

      %{query: query} = URI.parse(location)
      params = URI.decode_query(query)

      assert params["client_id"] == "test-client-id"
      assert params["response_type"] == "code"
      assert params["state"] == get_session(conn, :spotify_oauth_state)
      assert params["state"] != nil

      # The wide taste pool depends on these being granted up front.
      scopes = String.split(params["scope"], " ")
      assert "user-top-read" in scopes
      assert "user-follow-read" in scopes
      assert "user-library-read" in scopes
      assert "user-read-email" in scopes
    end

    test "issues a different state each time", %{conn: conn} do
      first = conn |> get(~p"/auth/spotify") |> get_session(:spotify_oauth_state)
      second = conn |> get(~p"/auth/spotify") |> get_session(:spotify_oauth_state)

      refute first == second
    end
  end

  describe "GET /auth/spotify/callback" do
    test "logs the user in when the state matches", %{conn: conn} do
      stub_spotify()

      conn =
        conn
        |> init_test_session(spotify_oauth_state: "the-state")
        |> get(~p"/auth/spotify/callback", %{"code" => "the-code", "state" => "the-state"})

      assert redirected_to(conn) == ~p"/home"

      user = Repo.get_by!(User, spotify_id: "spotify-abc")
      assert get_session(conn, :user_id) == user.id
      assert user.access_token == "new-access-token"
      assert user.refresh_token == "new-refresh-token"

      # The one-shot state must not survive to authorize a second callback.
      refute get_session(conn, :spotify_oauth_state)
    end

    test "rejects a mismatched state without creating a user", %{conn: conn} do
      conn =
        conn
        |> init_test_session(spotify_oauth_state: "the-real-state")
        |> get(~p"/auth/spotify/callback", %{"code" => "the-code", "state" => "an-attacker"})

      assert redirected_to(conn) == ~p"/"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "expired"
      refute get_session(conn, :user_id)
      assert Repo.aggregate(User, :count) == 0
    end

    test "rejects a callback when no state was ever issued", %{conn: conn} do
      conn =
        conn
        |> init_test_session(%{})
        |> get(~p"/auth/spotify/callback", %{"code" => "the-code", "state" => "invented"})

      assert redirected_to(conn) == ~p"/"
      refute get_session(conn, :user_id)
    end

    test "handles the user declining on Spotify's consent screen", %{conn: conn} do
      conn = get(conn, ~p"/auth/spotify/callback", %{"error" => "access_denied"})

      assert redirected_to(conn) == ~p"/"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "cancelled"
    end

    test "explains the five-user cap when Spotify refuses the account", %{conn: conn} do
      stub_spotify(me_status: 403)

      conn =
        conn
        |> init_test_session(spotify_oauth_state: "the-state")
        |> get(~p"/auth/spotify/callback", %{"code" => "the-code", "state" => "the-state"})

      assert redirected_to(conn) == ~p"/"

      # A bare "login failed" here would send you hunting through your own code
      # for a problem that lives in the Spotify dashboard.
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "five"
      assert Repo.aggregate(User, :count) == 0
    end
  end

  describe "DELETE /auth/logout" do
    test "clears the session", %{conn: conn} do
      user = user_fixture()

      conn =
        conn
        |> init_test_session(user_id: user.id)
        |> delete(~p"/auth/logout")

      assert redirected_to(conn) == ~p"/"
      refute get_session(conn, :user_id)
    end
  end

  describe "authentication gate" do
    test "anonymous visitors are bounced off /home", %{conn: conn} do
      conn = get(conn, ~p"/home")

      assert redirected_to(conn) == ~p"/"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Log in with Spotify"
    end

    test "logged-in users reach /home", %{conn: conn} do
      user = user_fixture(%{display_name: "Stevie"})

      conn =
        conn
        |> init_test_session(user_id: user.id)
        |> get(~p"/home")

      assert html_response(conn, 200) =~ "Stevie"
    end
  end
end
