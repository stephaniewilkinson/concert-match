defmodule ConcertMatch.Repo.Migrations.AddObanJobsTable do
  use Ecto.Migration

  def up, do: Oban.Migration.up()

  # Rolling all the way back drops the jobs table entirely; bounded here so
  # `mix ecto.rollback` during development doesn't discard queued work.
  def down, do: Oban.Migration.down(version: 1)
end
