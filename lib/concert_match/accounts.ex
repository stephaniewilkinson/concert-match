defmodule ConcertMatch.Accounts do
  @moduledoc """
  Users and their Spotify credentials.
  """

  import Ecto.Query, warn: false

  alias ConcertMatch.Accounts.User
  alias ConcertMatch.Geocoding
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

  A first login seeds the email from Spotify. Later logins refresh credentials
  and profile details but leave the email alone, since by then it may have been
  changed in settings.
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
      user -> user |> User.relogin_changeset(attrs) |> Repo.update()
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

  @doc """
  Save settings, geocoding the postal code if it changed.

  The lookup happens here rather than in the changeset because it's a network
  call, and a changeset that reaches out to the internet is a changeset you
  can't reason about or test in isolation. Coordinates are only touched when
  the postal code actually changes, so saving an email doesn't re-geocode.
  """
  def update_settings(%User{} = user, attrs) do
    changeset = User.settings_changeset(user, attrs)

    case resolve_postal_code(changeset) do
      {:ok, changeset} -> Repo.update(changeset)
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp resolve_postal_code(changeset) do
    case Ecto.Changeset.get_change(changeset, :postal_code) do
      nil ->
        {:ok, changeset}

      code ->
        case Geocoding.lookup(code) do
          {:ok, place} ->
            {:ok,
             changeset
             |> Ecto.Changeset.put_change(:home_lat, place.lat)
             |> Ecto.Changeset.put_change(:home_lng, place.lng)
             |> Ecto.Changeset.put_change(:postal_place, place.place)}

          {:error, :not_found} ->
            {:error,
             changeset
             |> Ecto.Changeset.add_error(:postal_code, "isn't a postal code we can find")
             |> Map.put(:action, :update)}

          # Not the user's fault, so don't tell them their input is wrong.
          {:error, _reason} ->
            {:error,
             changeset
             |> Ecto.Changeset.add_error(
               :postal_code,
               "couldn't be looked up just now — try again in a moment"
             )
             |> Map.put(:action, :update)}
        end
    end
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
