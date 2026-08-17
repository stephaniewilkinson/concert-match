defmodule ConcertMatch.Repo.Migrations.DropFollowedTasteRows do
  use Ecto.Migration

  @moduledoc """
  Follows no longer count towards the taste pool.

  A refresh replaces a user's pool wholesale, so these rows would clear
  themselves on the next import anyway — but until then they would keep
  matching people to shows on the strength of a follow, now scoring zero
  because nothing adds the weight any more. Clearing them here makes the
  change take effect on deploy rather than whenever someone next imports.
  """

  def up do
    execute "DELETE FROM user_artists WHERE source = 'followed'"
  end

  # Nothing to restore: the data came from Spotify, and an import brings back
  # whatever is current.
  def down, do: :ok
end
