defmodule ConcertMatch.Music.UserArtist do
  @moduledoc """
  One reason to believe a user cares about an artist.

  A single artist can produce several of these rows for one user — a placement
  in each of the three time ranges, plus a library presence. They are kept
  separate rather than collapsed so the affinity score can weigh them.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias ConcertMatch.Accounts.User
  alias ConcertMatch.Music.Artist

  @sources ~w(top_short top_medium top_long library)

  @type t :: %__MODULE__{}

  schema "user_artists" do
    belongs_to :user, User
    belongs_to :artist, Artist

    field :source, :string
    field :rank, :integer
    field :refreshed_at, :utc_datetime
  end

  def sources, do: @sources

  def changeset(user_artist, attrs) do
    user_artist
    |> cast(attrs, [:user_id, :artist_id, :source, :rank, :refreshed_at])
    |> validate_required([:user_id, :artist_id, :source, :refreshed_at])
    |> validate_inclusion(:source, @sources)
    |> unique_constraint([:user_id, :artist_id, :source])
  end
end
