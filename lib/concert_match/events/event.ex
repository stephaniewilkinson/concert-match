defmodule ConcertMatch.Events.Event do
  @moduledoc """
  A concert, as reported by one event source.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias ConcertMatch.Music.Artist

  @type t :: %__MODULE__{}

  schema "events" do
    field :source, :string
    field :source_event_id, :string
    field :name, :string
    field :starts_at, :utc_datetime
    field :venue_name, :string
    field :city, :string
    field :lat, :float
    field :lng, :float
    field :url, :string
    field :image_url, :string
    field :first_seen_at, :utc_datetime

    many_to_many :artists, Artist, join_through: "event_artists"

    timestamps(type: :utc_datetime)
  end

  def changeset(event, attrs) do
    event
    |> cast(attrs, [
      :source,
      :source_event_id,
      :name,
      :starts_at,
      :venue_name,
      :city,
      :lat,
      :lng,
      :url,
      :image_url,
      :first_seen_at
    ])
    |> validate_required([:source, :source_event_id, :name, :first_seen_at])
    |> unique_constraint([:source, :source_event_id])
  end
end
