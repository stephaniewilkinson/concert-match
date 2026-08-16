defmodule ConcertMatchWeb.HealthController do
  @moduledoc """
  What Render polls to decide whether this instance is alive.

  Checks the database rather than just returning 200, because a web process
  that can't reach Postgres can't do anything useful here — every page and
  every background job needs it.
  """

  use ConcertMatchWeb, :controller

  alias ConcertMatch.Repo

  def index(conn, _params) do
    case Ecto.Adapters.SQL.query(Repo, "SELECT 1", []) do
      {:ok, _} -> send_resp(conn, 200, "ok")
      {:error, _} -> send_resp(conn, 503, "database unavailable")
    end
  end
end
