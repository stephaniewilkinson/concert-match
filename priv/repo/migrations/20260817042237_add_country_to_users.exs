defmodule ConcertMatch.Repo.Migrations.AddCountryToUsers do
  use Ecto.Migration

  @moduledoc """
  Postal codes only mean something alongside a country. 97214 is in Portland;
  it is also not a valid code in most of the world.

  Defaults to "us" because that's what the existing rows are, and because the
  geocoder needed a country before this column existed and was hardcoded to it.
  """

  def change do
    alter table(:users) do
      add :country, :text, null: false, default: "us"
    end
  end
end
