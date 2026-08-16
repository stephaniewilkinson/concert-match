defmodule ConcertMatch.AccountsFixtures do
  @moduledoc """
  Test fixtures for `ConcertMatch.Accounts`.
  """

  alias ConcertMatch.Accounts
  alias ConcertMatch.Repo

  def user_fixture(attrs \\ %{}) do
    spotify_id = attrs[:spotify_id] || "spotify-#{System.unique_integer([:positive])}"

    defaults = %{
      spotify_id: spotify_id,
      display_name: "Test User",
      email: "#{spotify_id}@example.com",
      access_token: "access-token",
      refresh_token: "refresh-token",
      token_expires_at: DateTime.utc_now() |> DateTime.add(3600) |> DateTime.truncate(:second),
      home_lat: 45.5231,
      home_lng: -122.6765,
      radius_miles: 50,
      notify_enabled: true
    }

    %Accounts.User{}
    |> Ecto.Changeset.change(Map.merge(defaults, Map.new(attrs)))
    |> Repo.insert!()
  end

  @doc "A user whose access token lapsed an hour ago."
  def expired_user_fixture(attrs \\ %{}) do
    expired = DateTime.utc_now() |> DateTime.add(-3600) |> DateTime.truncate(:second)
    user_fixture(Map.merge(Map.new(attrs), %{token_expires_at: expired}))
  end

  @doc "A Spotify `/v1/me` payload."
  def spotify_profile(overrides \\ %{}) do
    Map.merge(
      %{
        "id" => "spotify-abc",
        "display_name" => "Stevie",
        "email" => "stevie@example.com",
        "images" => [%{"url" => "https://example.com/avatar.jpg"}]
      },
      overrides
    )
  end

  @doc "A Spotify token-endpoint payload."
  def spotify_tokens(overrides \\ %{}) do
    Map.merge(
      %{
        "access_token" => "new-access-token",
        "refresh_token" => "new-refresh-token",
        "expires_in" => 3600,
        "token_type" => "Bearer"
      },
      overrides
    )
  end
end
