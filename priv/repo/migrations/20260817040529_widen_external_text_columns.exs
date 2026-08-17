defmodule ConcertMatch.Repo.Migrations.WidenExternalTextColumns do
  use Ecto.Migration

  @moduledoc """
  Ecto's `:string` maps to varchar(255), which is too small for several values
  these APIs actually return.

  The one that broke production was `users.access_token`: Spotify's access
  tokens are comfortably past 255 characters, so every login 500'd with

      ERROR 22001 (string_data_right_truncation)
      value too long for type character varying(255)

  Ticketmaster's event and image URLs carry tracking parameters and would have
  been next, on the first sweep that found a show.

  In Postgres, text and varchar(n) are stored identically and perform
  identically -- varchar(n) is only a constraint. There is no reason to impose
  one on a value whose length is somebody else's decision, so everything
  sourced from an external API becomes text here. The two columns left alone,
  `events.source` and `user_artists.source`, are our own vocabulary, where the
  constraint is the point.
  """

  @widened [
    {:users, [:access_token, :refresh_token, :avatar_url, :display_name, :email, :spotify_id]},
    {:artists, [:name, :normalized_name, :image_url, :spotify_id]},
    {:events, [:name, :venue_name, :city, :url, :image_url, :source_event_id]}
  ]

  def up do
    for {table, columns} <- @widened, column <- columns do
      alter table(table) do
        modify column, :text
      end
    end
  end

  def down do
    # Truncating on the way back down would corrupt data rather than restore
    # it, so this narrows the type and lets Postgres refuse if anything no
    # longer fits.
    for {table, columns} <- @widened, column <- columns do
      alter table(table) do
        modify column, :string
      end
    end
  end
end
