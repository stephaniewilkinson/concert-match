defmodule ConcertMatch.Repo.Migrations.AddPostalCodeToUsers do
  use Ecto.Migration

  @moduledoc """
  A postal code is what someone can actually answer when asked where they live.

  Latitude and longitude stay: the event sweep works in coordinates, and so
  will a map. They're now derived by geocoding the postal code on save rather
  than typed in by hand. Existing users keep whatever coordinates they already
  had until they set a postal code.
  """

  def change do
    alter table(:users) do
      add :postal_code, :text
      # Whatever the geocoder called this place -- "Portland, Oregon". Shown
      # back to the user so a typo that resolves to somewhere real is still
      # obvious.
      add :postal_place, :text
    end
  end
end
