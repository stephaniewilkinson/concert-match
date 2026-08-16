defmodule ConcertMatch.Accounts do
  @moduledoc """
  Users and their Spotify credentials.
  """

  import Ecto.Query, warn: false

  alias ConcertMatch.Accounts.User
  alias ConcertMatch.Repo
  alias ConcertMatch.Spotify.OAuth

  # Refresh slightly before Spotify's stated expiry so a token can't lapse
  # mid-request during a long nightly sweep.
  @expiry_margin_seconds 60

  def list_users, do: Repo.all(User)

  def get_user!(id), do: Repo.get!(User, id)

  def get_user(id), do: Repo.get(User, id)

  def get_user_by_spotify_id(spotify_id), do: Repo.get_by(User, spotify_id: spotify_id)

  @doc """
  Create or update the user behind a Spotify login.

  Keyed on `spotify_id`, so logging in twice updates one row. The 2016 version
  of this app called `user.save()` without returning and fell through to
  `new User(...)`, minting a duplicate on every re-login; that shape is not
  expressible here, and a unique index backs it up.
  """
  def upsert_from_spotify(profile, tokens) do
    attrs = %{
      spotify_id: profile["id"],
      display_name: profile["display_name"],
      email: profile["email"],
      avatar_url: avatar_url(profile),
      access_token: tokens["access_token"],
      refresh_token: tokens["refresh_token"],
      token_expires_at: expires_at(tokens["expires_in"])
    }

    case get_user_by_spotify_id(profile["id"]) do
      nil -> %User{} |> User.oauth_changeset(attrs) |> Repo.insert()
      user -> user |> User.oauth_changeset(attrs) |> Repo.update()
    end
  end

  @doc """
  An access token that is good right now, refreshing it first if needed.

  Every caller that talks to Spotify on a user's behalf should go through this
  rather than reading `user.access_token` directly. Tokens last an hour, which
  is shorter than the gap between nightly runs.
  """
  @spec fresh_access_token(User.t()) :: {:ok, String.t(), User.t()} | {:error, term()}
  def fresh_access_token(%User{} = user) do
    if token_valid?(user) do
      {:ok, user.access_token, user}
    else
      refresh_tokens(user)
    end
  end

  @doc """
  Whether the stored access token is still usable.
  """
  def token_valid?(%User{token_expires_at: nil}), do: false

  def token_valid?(%User{token_expires_at: expires_at}) do
    DateTime.compare(expires_at, DateTime.utc_now()) == :gt
  end

  @doc """
  Exchange the stored refresh token for a new access token and persist both.
  """
  def refresh_tokens(%User{refresh_token: nil}), do: {:error, :no_refresh_token}

  def refresh_tokens(%User{} = user) do
    with {:ok, tokens} <- OAuth.refresh(user.refresh_token),
         attrs = %{
           access_token: tokens["access_token"],
           # Spotify rotates this only sometimes; the changeset ignores a nil
           # rather than wiping the token the background jobs depend on.
           refresh_token: tokens["refresh_token"],
           token_expires_at: expires_at(tokens["expires_in"])
         },
         {:ok, user} <- user |> User.token_changeset(attrs) |> Repo.update() do
      {:ok, user.access_token, user}
    end
  end

  def update_settings(%User{} = user, attrs) do
    user |> User.settings_changeset(attrs) |> Repo.update()
  end

  def change_settings(%User{} = user, attrs \\ %{}) do
    User.settings_changeset(user, attrs)
  end

  @doc """
  Users who can actually be matched and mailed: a home location and email on.
  """
  def notifiable_users do
    Repo.all(
      from u in User,
        where: u.notify_enabled and not is_nil(u.home_lat) and not is_nil(u.home_lng)
    )
  end

  @doc """
  The distinct places to sweep for events.

  Ticketmaster calls scale with this list, not with the artist pool, which is
  what keeps a nightly run in the tens of requests.
  """
  def distinct_search_areas do
    Repo.all(
      from u in User,
        where: not is_nil(u.home_lat) and not is_nil(u.home_lng),
        group_by: [u.home_lat, u.home_lng, u.radius_miles],
        select: %{lat: u.home_lat, lng: u.home_lng, radius_miles: u.radius_miles}
    )
  end

  defp expires_at(nil), do: nil

  defp expires_at(expires_in) when is_integer(expires_in) do
    DateTime.utc_now()
    |> DateTime.add(expires_in - @expiry_margin_seconds, :second)
    |> DateTime.truncate(:second)
  end

  defp avatar_url(%{"images" => [%{"url" => url} | _]}), do: url
  defp avatar_url(_), do: nil
end
