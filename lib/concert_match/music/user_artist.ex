defmodule ConcertMatch.Music.UserArtist do
  @moduledoc """
  One reason to believe a user cares about an artist.

  A single artist can produce several of these rows for one user — a top-50
  placement in each time range, plus a follow, plus a library presence. They
  are kept separate rather than collapsed so the affinity score can weigh
  them, and so a shifting top-50 doesn't erase a deliberate follow.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias ConcertMatch.Accounts.User
  alias ConcertMatch.Music.Artist

  @sources ~w(top_short top_medium top_long followed library)

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
