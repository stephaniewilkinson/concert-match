defmodule ConcertMatch.Accounts.User do
  @moduledoc """
  A person who has authorized Concert Match against their Spotify account.

  There will never be many of these. Spotify caps development-mode apps at five
  authenticated users, and extended access has required a registered
  organization since May 2025, so the whole app is designed around a small,
  known group rather than a signup funnel.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "users" do
    field :spotify_id, :string
    field :display_name, :string
    field :email, :string
    field :avatar_url, :string

    field :access_token, :string
    field :refresh_token, :string
    field :token_expires_at, :utc_datetime

    field :home_lat, :float
    field :home_lng, :float
    field :radius_miles, :integer, default: 50

    field :notify_enabled, :boolean, default: true

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating or updating a user from a Spotify login.

  Spotify does not reissue a refresh token on every exchange, so a nil
  `refresh_token` here means "keep the one we already have" rather than
  "clear it". Dropping it would silently break every background job for that
  user, which is exactly the failure the old app shipped with.
  """
  def oauth_changeset(user, attrs) do
    user
    |> cast(attrs, [
      :spotify_id,
      :display_name,
      :email,
      :avatar_url,
      :access_token,
      :refresh_token,
      :token_expires_at
    ])
    |> validate_required([:spotify_id, :access_token, :token_expires_at])
    |> drop_nil_refresh_token()
    |> unique_constraint(:spotify_id)
  end

  @doc """
  Changeset for a token refresh, which touches nothing but the credentials.
  """
  def token_changeset(user, attrs) do
    user
    |> cast(attrs, [:access_token, :refresh_token, :token_expires_at])
    |> validate_required([:access_token, :token_expires_at])
    |> drop_nil_refresh_token()
  end

  @doc """
  Changeset for the settings page.
  """
  def settings_changeset(user, attrs) do
    user
    |> cast(attrs, [:home_lat, :home_lng, :radius_miles, :notify_enabled])
    |> validate_number(:home_lat, greater_than_or_equal_to: -90, less_than_or_equal_to: 90)
    |> validate_number(:home_lng, greater_than_or_equal_to: -180, less_than_or_equal_to: 180)
    |> validate_number(:radius_miles, greater_than: 0, less_than_or_equal_to: 500)
  end

  defp drop_nil_refresh_token(changeset) do
    case fetch_change(changeset, :refresh_token) do
      {:ok, nil} -> delete_change(changeset, :refresh_token)
      _ -> changeset
    end
  end
end
