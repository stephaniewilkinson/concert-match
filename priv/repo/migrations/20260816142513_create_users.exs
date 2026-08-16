defmodule ConcertMatch.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    create table(:users) do
      add :spotify_id, :string, null: false
      add :display_name, :string
      add :email, :string
      add :avatar_url, :string

      add :access_token, :string
      add :refresh_token, :string
      add :token_expires_at, :utc_datetime

      # Where to look for shows. Set from the browser's geolocation or the
      # settings page; until one is set, a user simply matches nothing.
      add :home_lat, :float
      add :home_lng, :float
      add :radius_miles, :integer, null: false, default: 50

      add :notify_enabled, :boolean, null: false, default: true

      timestamps(type: :utc_datetime)
    end

    # The 2016 app keyed users by provider id but never enforced it, and a bug
    # in its login callback inserted a fresh row on every re-login. The database
    # now refuses that outright.
    create unique_index(:users, [:spotify_id])
  end
end
