defmodule ConcertMatch.AccountsTest do
  use ConcertMatch.DataCase, async: true

  import ConcertMatch.AccountsFixtures

  alias ConcertMatch.Accounts
  alias ConcertMatch.Accounts.User
  alias ConcertMatch.Spotify.OAuth

  describe "upsert_from_spotify/2" do
    test "creates a user on first login" do
      assert {:ok, user} = Accounts.upsert_from_spotify(spotify_profile(), spotify_tokens())

      assert user.spotify_id == "spotify-abc"
      assert user.display_name == "Stevie"
      assert user.email == "stevie@example.com"
      assert user.avatar_url == "https://example.com/avatar.jpg"
      assert Repo.aggregate(User, :count) == 1
    end

    # The 2016 app called user.save() without returning and fell through to
    # `new User(...)`, so every re-login with a rotated token created another
    # row. This is that bug, expressed as a test.
    test "logging in again with a different token updates the same row" do
      {:ok, first} = Accounts.upsert_from_spotify(spotify_profile(), spotify_tokens())

      {:ok, second} =
        Accounts.upsert_from_spotify(
          spotify_profile(),
          spotify_tokens(%{"access_token" => "a-different-token"})
        )

      assert first.id == second.id
      assert second.access_token == "a-different-token"
      assert Repo.aggregate(User, :count) == 1
    end

    test "different Spotify accounts get their own rows" do
      {:ok, _} = Accounts.upsert_from_spotify(spotify_profile(), spotify_tokens())

      {:ok, _} =
        Accounts.upsert_from_spotify(
          spotify_profile(%{"id" => "spotify-xyz"}),
          spotify_tokens()
        )

      assert Repo.aggregate(User, :count) == 2
    end

    test "a profile without images does not blow up" do
      profile = spotify_profile() |> Map.delete("images")
      assert {:ok, user} = Accounts.upsert_from_spotify(profile, spotify_tokens())
      assert is_nil(user.avatar_url)
    end

    test "keeps the existing refresh token when Spotify omits one" do
      {:ok, first} = Accounts.upsert_from_spotify(spotify_profile(), spotify_tokens())
      assert first.refresh_token == "new-refresh-token"

      {:ok, second} =
        Accounts.upsert_from_spotify(
          spotify_profile(),
          spotify_tokens() |> Map.delete("refresh_token")
        )

      assert second.refresh_token == "new-refresh-token"
    end
  end

  describe "token_valid?/1" do
    test "true while the token is in date" do
      assert Accounts.token_valid?(user_fixture())
    end

    test "false once it has lapsed" do
      refute Accounts.token_valid?(expired_user_fixture())
    end

    test "false when there is no expiry recorded" do
      refute Accounts.token_valid?(%User{token_expires_at: nil})
    end
  end

  describe "fresh_access_token/1" do
    test "returns the stored token without a network call when still valid" do
      user = user_fixture(%{access_token: "still-good"})

      # No Req.Test stub is registered, so any HTTP call would fail the test.
      assert {:ok, "still-good", ^user} = Accounts.fresh_access_token(user)
    end

    test "refreshes and persists when the token has lapsed" do
      user = expired_user_fixture(%{refresh_token: "the-refresh-token"})

      Req.Test.stub(OAuth, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        params = URI.decode_query(body)

        assert params["grant_type"] == "refresh_token"
        assert params["refresh_token"] == "the-refresh-token"

        Req.Test.json(conn, spotify_tokens(%{"access_token" => "refreshed-token"}))
      end)

      assert {:ok, "refreshed-token", refreshed} = Accounts.fresh_access_token(user)
      assert refreshed.access_token == "refreshed-token"
      assert Accounts.token_valid?(refreshed)

      # Persisted, not just returned -- the background jobs reload from the DB.
      assert Repo.get!(User, user.id).access_token == "refreshed-token"
    end

    test "keeps the old refresh token when the refresh response omits one" do
      user = expired_user_fixture(%{refresh_token: "long-lived-token"})

      Req.Test.stub(OAuth, fn conn ->
        Req.Test.json(conn, spotify_tokens() |> Map.delete("refresh_token"))
      end)

      assert {:ok, _token, refreshed} = Accounts.fresh_access_token(user)

      # Wiping this would silently break every future nightly run for the user.
      assert refreshed.refresh_token == "long-lived-token"
    end

    test "stores a rotated refresh token when Spotify issues one" do
      user = expired_user_fixture(%{refresh_token: "old-token"})

      Req.Test.stub(OAuth, fn conn ->
        Req.Test.json(conn, spotify_tokens(%{"refresh_token" => "rotated-token"}))
      end)

      assert {:ok, _token, refreshed} = Accounts.fresh_access_token(user)
      assert refreshed.refresh_token == "rotated-token"
    end

    test "surfaces an error when the refresh is rejected" do
      user = expired_user_fixture()

      Req.Test.stub(OAuth, fn conn ->
        conn
        |> Plug.Conn.put_status(400)
        |> Req.Test.json(%{"error" => "invalid_grant"})
      end)

      assert {:error, {:http_error, 400, _}} = Accounts.fresh_access_token(user)
    end

    test "reports a missing refresh token rather than calling Spotify" do
      user = expired_user_fixture(%{refresh_token: nil})
      assert {:error, :no_refresh_token} = Accounts.fresh_access_token(user)
    end
  end

  describe "distinct_search_areas/0" do
    test "collapses users who live in the same place" do
      user_fixture(%{home_lat: 45.5231, home_lng: -122.6765, radius_miles: 50})
      user_fixture(%{home_lat: 45.5231, home_lng: -122.6765, radius_miles: 50})
      user_fixture(%{home_lat: 40.7128, home_lng: -74.006, radius_miles: 50})

      areas = Accounts.distinct_search_areas()

      # Two locations, not three users: this is what keeps the nightly
      # Ticketmaster spend proportional to cities rather than people.
      assert length(areas) == 2
    end

    test "ignores users who haven't set a location" do
      user_fixture(%{home_lat: nil, home_lng: nil})
      assert Accounts.distinct_search_areas() == []
    end

    test "treats different radii around one point as separate sweeps" do
      user_fixture(%{home_lat: 45.5231, home_lng: -122.6765, radius_miles: 25})
      user_fixture(%{home_lat: 45.5231, home_lng: -122.6765, radius_miles: 100})

      assert length(Accounts.distinct_search_areas()) == 2
    end
  end

  describe "notifiable_users/0" do
    test "excludes users who turned email off or have no location" do
      wanted = user_fixture()
      user_fixture(%{notify_enabled: false})
      user_fixture(%{home_lat: nil, home_lng: nil})

      assert [found] = Accounts.notifiable_users()
      assert found.id == wanted.id
    end
  end
end
