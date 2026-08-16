defmodule ConcertMatch.Notifications.Notification do
  @moduledoc """
  A record that we told someone about a show.

  Exists to be a uniqueness constraint. Without it, every nightly run would
  re-send the same digest, which is the fastest way to get an app filtered
  into a spam folder by its own users.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias ConcertMatch.Accounts.User
  alias ConcertMatch.Events.Event

  @type t :: %__MODULE__{}

  schema "notifications" do
    belongs_to :user, User
    belongs_to :event, Event

    field :sent_at, :utc_datetime
  end

  def changeset(notification, attrs) do
    notification
    |> cast(attrs, [:user_id, :event_id, :sent_at])
    |> validate_required([:user_id, :event_id, :sent_at])
    |> unique_constraint([:user_id, :event_id])
  end
end
