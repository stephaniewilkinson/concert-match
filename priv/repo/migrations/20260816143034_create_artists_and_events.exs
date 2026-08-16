defmodule ConcertMatch.Repo.Migrations.CreateArtistsAndEvents do
  use Ecto.Migration

  def change do
    create table(:artists) do
      add :spotify_id, :string, null: false
      add :name, :string, null: false
      # Casefolded, de-accented, punctuation-stripped. This is the join key
      # against event lineups, since Ticketmaster and Spotify agree on very
      # little else about how an artist's name is spelled.
      add :normalized_name, :string, null: false
      add :image_url, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:artists, [:spotify_id])
    create index(:artists, [:normalized_name])

    create table(:user_artists) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :artist_id, references(:artists, on_delete: :delete_all), null: false
      # top_short | top_medium | top_long | followed | library
      add :source, :string, null: false
      # 1-50 for the ranked sources, null for the rest.
      add :rank, :integer
      add :refreshed_at, :utc_datetime, null: false
    end

    # One row per source, so an artist can be both a #3 long-term favourite and
    # a follow without either fact overwriting the other.
    create unique_index(:user_artists, [:user_id, :artist_id, :source])
    create index(:user_artists, [:artist_id])

    create table(:events) do
      add :source, :string, null: false
      add :source_event_id, :string, null: false
      add :name, :string, null: false
      add :starts_at, :utc_datetime
      add :venue_name, :string
      add :city, :string
      add :lat, :float
      add :lng, :float
      add :url, :string
      add :image_url, :string
      # "Newly announced" means "we hadn't seen it before". Simpler than
      # interpreting onsale timestamps, and it stays correct if a second
      # event source is ever added.
      add :first_seen_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:events, [:source, :source_event_id])
    create index(:events, [:starts_at])

    create table(:event_artists) do
      add :event_id, references(:events, on_delete: :delete_all), null: false
      add :artist_id, references(:artists, on_delete: :delete_all), null: false
    end

    create unique_index(:event_artists, [:event_id, :artist_id])
    create index(:event_artists, [:artist_id])

    create table(:notifications) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :event_id, references(:events, on_delete: :delete_all), null: false
      add :sent_at, :utc_datetime, null: false
    end

    # The thing that stops a second nightly run re-emailing everyone about
    # shows they already heard about.
    create unique_index(:notifications, [:user_id, :event_id])
  end
end
