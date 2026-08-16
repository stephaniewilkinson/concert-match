defmodule ConcertMatch.Music.Artist do
  @moduledoc """
  An artist someone listens to, as Spotify knows them.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias ConcertMatch.Music.Name

  @type t :: %__MODULE__{}

  schema "artists" do
    field :spotify_id, :string
    field :name, :string
    field :normalized_name, :string
    field :image_url, :string

    timestamps(type: :utc_datetime)
  end

  def changeset(artist, attrs) do
    artist
    |> cast(attrs, [:spotify_id, :name, :image_url])
    |> validate_required([:spotify_id, :name])
    |> put_normalized_name()
    |> unique_constraint(:spotify_id)
  end

  # Derived, never supplied: the join key must not drift from the name.
  defp put_normalized_name(changeset) do
    case get_field(changeset, :name) do
      nil -> changeset
      name -> put_change(changeset, :normalized_name, Name.normalize(name))
    end
  end
end
