defmodule ConcertMatch.Spotify.Api do
  @moduledoc """
  The Spotify endpoints this app reads taste from.

  All of these survived Spotify's November 2024 cull, which took Related
  Artists, Recommendations, Audio Features, Audio Analysis, and the featured
  playlist endpoints away from development-mode apps. Anything added here
  should be checked against that list first.
  """

  @api_url "https://api.spotify.com/v1"

  # Spotify's ceiling for these endpoints.
  @page_size 50

  # Saved tracks and albums can run to thousands of items. Bounded so a user
  # with a decade of library doesn't turn one nightly job into a long crawl;
  # the artists past this point are the weakest signal in the pool anyway.
  @max_library_pages 40

  @doc """
  Top artists for one time range.

  Spotify documents the ordering only as "based on calculated affinity" — there
  is no published play threshold, and rank is meaningful within a user rather
  than across them. Position is returned so it can be used for sorting, which
  is all it can honestly support.
  """
  @spec top_artists(String.t(), String.t()) :: {:ok, [map()]} | {:error, term()}
  def top_artists(access_token, time_range)
      when time_range in ~w(short_term medium_term long_term) do
    get(access_token, "/me/top/artists", limit: @page_size, time_range: time_range)
    |> case do
      {:ok, %{"items" => items}} -> {:ok, items}
      {:ok, _} -> {:ok, []}
      error -> error
    end
  end

  @doc """
  Every artist the user follows. Cursor-paginated rather than offset-paginated.
  """
  @spec followed_artists(String.t()) :: {:ok, [map()]} | {:error, term()}
  def followed_artists(access_token) do
    follow_cursor(access_token, nil, [], 0)
  end

  @doc """
  Distinct artists across the user's saved tracks and saved albums.
  """
  @spec library_artists(String.t()) :: {:ok, [map()]} | {:error, term()}
  def library_artists(access_token) do
    with {:ok, track_artists} <- saved_tracks_artists(access_token),
         {:ok, album_artists} <- saved_albums_artists(access_token) do
      {:ok, dedupe(track_artists ++ album_artists)}
    end
  end

  defp saved_tracks_artists(access_token) do
    paginate(access_token, "/me/tracks", fn item ->
      get_in(item, ["track", "artists"]) || []
    end)
  end

  defp saved_albums_artists(access_token) do
    paginate(access_token, "/me/albums", fn item ->
      get_in(item, ["album", "artists"]) || []
    end)
  end

  # Offset pagination over a saved-items endpoint, extracting artists per item.
  defp paginate(access_token, path, extract, offset \\ 0, acc \\ [], page \\ 0)

  defp paginate(_access_token, _path, _extract, _offset, acc, page)
       when page >= @max_library_pages do
    {:ok, dedupe(acc)}
  end

  defp paginate(access_token, path, extract, offset, acc, page) do
    case get(access_token, path, limit: @page_size, offset: offset) do
      {:ok, %{"items" => []}} ->
        {:ok, dedupe(acc)}

      {:ok, %{"items" => items} = body} ->
        acc = acc ++ Enum.flat_map(items, extract)

        if is_nil(body["next"]) do
          {:ok, dedupe(acc)}
        else
          paginate(access_token, path, extract, offset + @page_size, acc, page + 1)
        end

      {:ok, _} ->
        {:ok, dedupe(acc)}

      error ->
        error
    end
  end

  defp follow_cursor(_access_token, _after_id, acc, page) when page >= @max_library_pages do
    {:ok, dedupe(acc)}
  end

  defp follow_cursor(access_token, after_id, acc, page) do
    params = [type: "artist", limit: @page_size]
    params = if after_id, do: Keyword.put(params, :after, after_id), else: params

    case get(access_token, "/me/following", params) do
      {:ok, %{"artists" => %{"items" => []}}} ->
        {:ok, dedupe(acc)}

      {:ok, %{"artists" => %{"items" => items} = artists}} ->
        acc = acc ++ items
        cursor = get_in(artists, ["cursors", "after"])

        if is_nil(cursor) do
          {:ok, dedupe(acc)}
        else
          follow_cursor(access_token, cursor, acc, page + 1)
        end

      {:ok, _} ->
        {:ok, dedupe(acc)}

      error ->
        error
    end
  end

  defp dedupe(artists), do: Enum.uniq_by(artists, & &1["id"])

  defp get(access_token, path, params) do
    [
      url: @api_url <> path,
      params: params,
      auth: {:bearer, access_token},
      # Spotify answers a burst with 429 and a Retry-After; Req honours it.
      retry: :safe_transient,
      max_retries: 3
    ]
    |> Keyword.merge(Application.get_env(:concert_match, :spotify_api_req_options, []))
    |> Req.request()
    |> case do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
