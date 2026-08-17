defmodule ConcertMatch.Spotify.OAuth do
  @moduledoc """
  Spotify's authorization-code flow, by hand.

  This is deliberately not built on Ueberauth. `ueberauth_spotify` was last
  released in 2019 and the flow is three HTTP calls, but the real reason is
  refresh: the nightly workers need to mint access tokens for users who aren't
  present, and that logic has to live here regardless of who owns the redirect.

  Set `SPOTIFY_CLIENT_ID`, `SPOTIFY_CLIENT_SECRET`, and `SPOTIFY_REDIRECT_URI`
  in the environment. The redirect URI must match the one registered on the
  Spotify app exactly, and Spotify rejects `localhost` in favour of `127.0.0.1`.
  """

  @accounts_url "https://accounts.spotify.com"
  @api_url "https://api.spotify.com/v1"

  # Only what's actually read. user-follow-read went when follows stopped
  # counting, and playlist-read-private was inherited from the 2016 app's
  # scope list and never used by anything here -- asking for a permission you
  # don't exercise is just a worse consent screen.
  @scopes ~w(
    user-top-read
    user-library-read
    user-read-email
  )

  @doc "The scopes this app requests."
  def scopes, do: @scopes

  @doc """
  Where to send the browser to begin authorization.

  `state` is echoed back to the callback and must be compared against the value
  held in the session; it is the only thing standing between this endpoint and
  a login-CSRF.
  """
  def authorize_url(state) do
    query =
      URI.encode_query(%{
        client_id: config!(:client_id),
        response_type: "code",
        redirect_uri: config!(:redirect_uri),
        scope: Enum.join(@scopes, " "),
        state: state
      })

    @accounts_url <> "/authorize?" <> query
  end

  @doc """
  Trade an authorization code for tokens.
  """
  @spec exchange_code(String.t()) :: {:ok, map()} | {:error, term()}
  def exchange_code(code) do
    token_request(%{
      grant_type: "authorization_code",
      code: code,
      redirect_uri: config!(:redirect_uri)
    })
  end

  @doc """
  Trade a refresh token for a fresh access token.

  Spotify may or may not return a new refresh token. When it doesn't, the
  caller must keep the existing one rather than overwriting it with nil.
  """
  @spec refresh(String.t()) :: {:ok, map()} | {:error, term()}
  def refresh(refresh_token) do
    token_request(%{grant_type: "refresh_token", refresh_token: refresh_token})
  end

  @doc """
  The authorizing user's profile, used to populate their account on first login.
  """
  @spec me(String.t()) :: {:ok, map()} | {:error, term()}
  def me(access_token) do
    [url: @api_url <> "/me", auth: {:bearer, access_token}]
    |> request()
    |> handle_response()
  end

  defp token_request(form) do
    [
      method: :post,
      url: @accounts_url <> "/api/token",
      form: form,
      auth: {:basic, "#{config!(:client_id)}:#{config!(:client_secret)}"}
    ]
    |> request()
    |> handle_response()
  end

  defp request(options) do
    options
    |> Keyword.merge(Application.get_env(:concert_match, :spotify_req_options, []))
    |> Req.request()
  end

  defp handle_response({:ok, %Req.Response{status: status, body: body}}) when status in 200..299,
    do: {:ok, body}

  defp handle_response({:ok, %Req.Response{status: status, body: body}}),
    do: {:error, {:http_error, status, body}}

  defp handle_response({:error, reason}), do: {:error, reason}

  defp config!(key) do
    :concert_match
    |> Application.fetch_env!(:spotify)
    |> Keyword.fetch!(key)
    |> case do
      nil ->
        raise """
        Spotify #{key} is not configured.

        Copy .env.example to .env, fill in your credentials from
        https://developer.spotify.com/dashboard, and load it into your shell.
        """

      value ->
        value
    end
  end
end
