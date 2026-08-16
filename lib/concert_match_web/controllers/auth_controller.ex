defmodule ConcertMatchWeb.AuthController do
  @moduledoc """
  The Spotify authorization-code round trip.
  """

  use ConcertMatchWeb, :controller

  require Logger

  alias ConcertMatch.Accounts
  alias ConcertMatch.Spotify.OAuth
  alias ConcertMatchWeb.UserAuth

  @doc """
  Kick off authorization, stashing a random state in the session to compare
  against on the way back.
  """
  def request(conn, _params) do
    state = 32 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)

    conn
    |> put_session(:spotify_oauth_state, state)
    |> redirect(external: OAuth.authorize_url(state))
  end

  @doc """
  Handle the redirect back from Spotify.
  """
  def callback(conn, %{"code" => code, "state" => state}) do
    expected = get_session(conn, :spotify_oauth_state)

    # Constant-time compare, and a nil expected state never matches.
    if is_binary(expected) and Plug.Crypto.secure_compare(state, expected) do
      conn |> delete_session(:spotify_oauth_state) |> complete_login(code)
    else
      Logger.warning("Spotify callback with mismatched state")
      fail(conn, "That login attempt expired. Try again.")
    end
  end

  def callback(conn, %{"error" => error}) do
    # The user pressed "Cancel" on Spotify's consent screen, most likely.
    Logger.info("Spotify callback returned error: #{error}")
    fail(conn, "Spotify login was cancelled.")
  end

  def callback(conn, _params), do: fail(conn, "Spotify login failed.")

  def delete(conn, _params) do
    UserAuth.log_out_user(conn)
  end

  defp complete_login(conn, code) do
    with {:ok, tokens} <- OAuth.exchange_code(code),
         {:ok, profile} <- OAuth.me(tokens["access_token"]),
         {:ok, user} <- Accounts.upsert_from_spotify(profile, tokens) do
      UserAuth.log_in_user(conn, user)
    else
      {:error, reason} ->
        Logger.error("Spotify login failed: #{inspect(reason)}")
        fail(conn, spotify_error_message(reason))
    end
  end

  # Spotify returns 403 from /v1/me when the account isn't on the app's
  # allowlist, which for a development-mode app is the single most likely
  # failure and the least self-explanatory. Say what it actually means.
  defp spotify_error_message({:http_error, 403, _body}) do
    "Spotify refused that account. Development-mode apps are limited to five " <>
      "users, each added by hand in the Spotify dashboard."
  end

  defp spotify_error_message(_reason), do: "Could not log in with Spotify. Try again."

  defp fail(conn, message) do
    conn
    |> put_flash(:error, message)
    |> redirect(to: ~p"/")
  end
end
