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
  Top artists for one time range, in rank order.

  Spotify caps `limit` at 50, so anything deeper is paged with `offset`. Fewer
  than `want` may come back: `total` is whatever Spotify's affinity data
  actually holds for that person and window, and a new account or a short
  window will simply have less.

  Spotify documents the ordering only as "based on calculated affinity" — there
  is no published play threshold, and rank is meaningful within a user rather
  than across them. Position is returned so it can be used for sorting, which
  is all it can honestly support.
  """
  @spec top_artists(String.t(), String.t(), pos_integer()) ::
          {:ok, [map()]} | {:error, term()}
  def top_artists(access_token, time_range, want \\ 50)
      when time_range in ~w(short_term medium_term long_term) do
    page_top_artists(access_token, time_range, want, 0, [])
  end

  defp page_top_artists(access_token, time_range, want, offset, acc) do
    remaining = want - length(acc)

    if remaining <= 0 do
      {:ok, acc}
    else
      params = [
        limit: min(remaining, @page_size),
        offset: offset,
        time_range: time_range
      ]

      case get(access_token, "/me/top/artists", params) do
        {:ok, %{"items" => []}} ->
          {:ok, acc}

        {:ok, %{"items" => items} = body} ->
          acc = acc ++ items

          # Stop on the last page rather than requesting an empty one. Ranking
          # depends on order, so pages must be appended in sequence.
          if is_nil(body["next"]) do
            {:ok, acc}
          else
            page_top_artists(access_token, time_range, want, offset + length(items), acc)
          end

        {:ok, _} ->
          {:ok, acc}

        error ->
          error
      end
    end
  end

  @doc """
  Distinct artists across the user's saved tracks and saved albums.

  `on_progress` is called with `{:library, count_so_far}` as each page lands.
  This is the slow part of an import — a decade of saved tracks is dozens of
  round trips — so it's the part worth reporting on.
  """
  @spec library_artists(String.t(), (term() -> any())) :: {:ok, [map()]} | {:error, term()}
  def library_artists(access_token, on_progress \\ fn _ -> :ok end) do
    with {:ok, track_artists} <- saved_tracks_artists(access_token, on_progress),
         {:ok, album_artists} <- saved_albums_artists(access_token, on_progress) do
      {:ok, dedupe(track_artists ++ album_artists)}
    end
  end

  defp saved_tracks_artists(access_token, on_progress) do
    paginate(
      access_token,
      "/me/tracks",
      fn item -> get_in(item, ["track", "artists"]) || [] end,
      on_progress
    )
  end

  defp saved_albums_artists(access_token, on_progress) do
    paginate(
      access_token,
      "/me/albums",
      fn item -> get_in(item, ["album", "artists"]) || [] end,
      on_progress
    )
  end

  # Offset pagination over a saved-items endpoint, extracting artists per item.
  defp paginate(access_token, path, extract, on_progress, offset \\ 0, acc \\ [], page \\ 0)

  defp paginate(_access_token, _path, _extract, _on_progress, _offset, acc, page)
       when page >= @max_library_pages do
    {:ok, dedupe(acc)}
  end

  defp paginate(access_token, path, extract, on_progress, offset, acc, page) do
    case get(access_token, path, limit: @page_size, offset: offset) do
      {:ok, %{"items" => []}} ->
        {:ok, dedupe(acc)}

      {:ok, %{"items" => items} = body} ->
        acc = acc ++ Enum.flat_map(items, extract)
        on_progress.({:library, length(dedupe(acc))})

        if is_nil(body["next"]) do
          {:ok, dedupe(acc)}
        else
          paginate(access_token, path, extract, on_progress, offset + @page_size, acc, page + 1)
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
