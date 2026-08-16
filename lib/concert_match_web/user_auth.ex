defmodule ConcertMatchWeb.UserAuth do
  @moduledoc """
  Session handling for logged-in users, in both plug and LiveView form.
  """

  use ConcertMatchWeb, :verified_routes

  import Plug.Conn
  import Phoenix.Controller

  alias ConcertMatch.Accounts

  @doc """
  Log a user in, renewing the session to avoid session fixation.
  """
  def log_in_user(conn, user) do
    conn
    |> renew_session()
    |> put_session(:user_id, user.id)
    |> redirect(to: ~p"/home")
  end

  def log_out_user(conn) do
    conn
    |> renew_session()
    |> redirect(to: ~p"/")
  end

  @doc """
  Assign `:current_user` from the session, or nil.
  """
  def fetch_current_user(conn, _opts) do
    user = conn |> get_session(:user_id) |> load_user()
    assign(conn, :current_user, user)
  end

  @doc """
  Halt anonymous requests to pages that need an account.
  """
  def require_authenticated_user(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
    else
      conn
      |> put_flash(:error, "Log in with Spotify to see your matches.")
      |> redirect(to: ~p"/")
      |> halt()
    end
  end

  @doc """
  LiveView equivalent of `fetch_current_user/2`, for `live_session`.
  """
  def on_mount(:mount_current_user, _params, session, socket) do
    {:cont,
     Phoenix.Component.assign_new(socket, :current_user, fn ->
       session |> Map.get("user_id") |> load_user()
     end)}
  end

  def on_mount(:ensure_authenticated, _params, session, socket) do
    socket =
      Phoenix.Component.assign_new(socket, :current_user, fn ->
        session |> Map.get("user_id") |> load_user()
      end)

    if socket.assigns.current_user do
      {:cont, socket}
    else
      {:halt,
       socket
       |> Phoenix.LiveView.put_flash(:error, "Log in with Spotify to see your matches.")
       |> Phoenix.LiveView.redirect(to: ~p"/")}
    end
  end

  defp load_user(nil), do: nil
  defp load_user(user_id), do: Accounts.get_user(user_id)

  # Wipes the session but preserves the live socket id so LiveViews reconnect
  # cleanly rather than holding a stale identity.
  defp renew_session(conn) do
    delete_csrf_token()

    conn
    |> configure_session(renew: true)
    |> clear_session()
  end
end
