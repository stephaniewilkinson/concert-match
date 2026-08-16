defmodule ConcertMatch.Events.Sources.Ticketmaster do
  @moduledoc """
  Ticketmaster Discovery API v2.

  Free tier: 5000 calls/day at 5 requests/second. This app sweeps by location
  rather than by artist, so a nightly run costs a handful of calls per city
  the users live in, not one per artist — which is what keeps a pool of a few
  thousand artists free.
  """

  @behaviour ConcertMatch.Events.Source

  @base_url "https://app.ticketmaster.com/discovery/v2"

  # Discovery refuses deep paging beyond `size * page < 1000`, so 200 x 5 is
  # the whole reachable result set. Any city with more than 1000 upcoming
  # music events in the window will be truncated; that is the API's ceiling,
  # not a choice.
  @page_size 200
  @max_pages 5

  @impl true
  def name, do: "ticketmaster"

  @impl true
  def fetch_events(%{lat: lat, lng: lng, radius_miles: radius}) do
    fetch_pages(lat, lng, radius, 0, [])
  end

  defp fetch_pages(_lat, _lng, _radius, page, acc) when page >= @max_pages do
    {:ok, acc}
  end

  defp fetch_pages(lat, lng, radius, page, acc) do
    params = [
      apikey: api_key!(),
      latlong: "#{lat},#{lng}",
      radius: radius,
      unit: "miles",
      classificationName: "music",
      # Ticketmaster will happily return last year's shows otherwise.
      startDateTime: now_iso8601(),
      sort: "date,asc",
      size: @page_size,
      page: page
    ]

    case get("/events.json", params) do
      {:ok, body} ->
        events = body |> extract_events() |> Enum.map(&normalize_event/1)
        acc = acc ++ events

        if last_page?(body, page) do
          {:ok, acc}
        else
          fetch_pages(lat, lng, radius, page + 1, acc)
        end

      error ->
        error
    end
  end

  defp extract_events(body), do: get_in(body, ["_embedded", "events"]) || []

  defp last_page?(body, page) do
    total_pages = get_in(body, ["page", "totalPages"]) || 0
    extract_events(body) == [] or page + 1 >= total_pages
  end

  @doc false
  # Public for testing: this is the shape-mapping that breaks when Ticketmaster
  # changes a field, and it is worth asserting against recorded payloads.
  def normalize_event(event) do
    venue = event |> get_in(["_embedded", "venues"]) |> first_or_nil()

    %{
      source: name(),
      source_event_id: event["id"],
      name: event["name"],
      artist_names: artist_names(event),
      starts_at: parse_start(event),
      venue_name: venue && venue["name"],
      city: venue && get_in(venue, ["city", "name"]),
      lat: venue |> location("latitude"),
      lng: venue |> location("longitude"),
      url: event["url"],
      image_url: event |> image_url()
    }
  end

  # Attractions are Ticketmaster's performers. Falling back to the event name
  # matters: plenty of small listings carry no attractions at all, and the
  # event name is often just the artist.
  defp artist_names(event) do
    case get_in(event, ["_embedded", "attractions"]) do
      attractions when is_list(attractions) and attractions != [] ->
        Enum.map(attractions, & &1["name"])

      _ ->
        [event["name"]]
    end
  end

  # Prefer the venue's local date-time; fall back to the UTC stamp. A show with
  # neither is kept rather than dropped, since it can still be a match.
  defp parse_start(event) do
    utc = get_in(event, ["dates", "start", "dateTime"])

    case utc && DateTime.from_iso8601(utc) do
      {:ok, datetime, _offset} -> DateTime.truncate(datetime, :second)
      _ -> nil
    end
  end

  defp location(nil, _key), do: nil

  defp location(venue, key) do
    case get_in(venue, ["location", key]) do
      value when is_binary(value) ->
        case Float.parse(value) do
          {float, _} -> float
          :error -> nil
        end

      value when is_float(value) ->
        value

      _ ->
        nil
    end
  end

  # Ticketmaster returns a spread of crops; take the widest 16:9 available so
  # the digest email isn't rendering thumbnails.
  defp image_url(event) do
    (event["images"] || [])
    |> Enum.filter(&(&1["ratio"] == "16_9"))
    |> Enum.max_by(& &1["width"], fn -> first_or_nil(event["images"]) end)
    |> case do
      nil -> nil
      image -> image["url"]
    end
  end

  defp first_or_nil([first | _]), do: first
  defp first_or_nil(_), do: nil

  defp now_iso8601 do
    DateTime.utc_now()
    |> DateTime.truncate(:second)
    |> DateTime.to_iso8601()
    |> String.replace("+00:00", "Z")
  end

  defp get(path, params) do
    [
      url: @base_url <> path,
      params: params,
      # Discovery rate-limits at 5 req/sec and answers with 429.
      retry: :safe_transient,
      max_retries: 3
    ]
    |> Keyword.merge(Application.get_env(:concert_match, :ticketmaster_req_options, []))
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

  defp api_key! do
    :concert_match
    |> Application.fetch_env!(:ticketmaster)
    |> Keyword.fetch!(:api_key)
    |> case do
      nil ->
        raise """
        Ticketmaster API key is not configured.

        Get a free one at https://developer.ticketmaster.com and set
        TICKETMASTER_API_KEY in your environment.
        """

      key ->
        key
    end
  end
end
