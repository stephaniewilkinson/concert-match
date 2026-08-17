defmodule ConcertMatch.Geocoding.Zippopotam do
  @moduledoc """
  Postal code lookup via api.zippopotam.us.

  Free and keyless, which is why it's here — the alternatives either want an
  API key or a 1.5MB dataset committed to the repo, and this is one lookup per
  person per time they move house.

  Being free and keyless also means it owes us nothing. `ConcertMatch.Geocoding`
  is a behaviour so replacing it is a new module, not a rewrite.
  """

  @behaviour ConcertMatch.Geocoding

  @base_url "https://api.zippopotam.us"

  @impl true
  def lookup(postal_code, country) do
    url = "#{@base_url}/#{String.downcase(country)}/#{URI.encode(postal_code)}"

    [url: url, retry: :safe_transient, max_retries: 2]
    |> Keyword.merge(Application.get_env(:concert_match, :geocoding_req_options, []))
    |> Req.request()
    |> case do
      {:ok, %Req.Response{status: 200, body: body}} ->
        parse(body)

      # Zippopotam answers an unknown code with 404 and an empty body.
      {:ok, %Req.Response{status: 404}} ->
        {:error, :not_found}

      {:ok, %Req.Response{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse(%{"places" => [place | _]}) do
    with {lat, _} <- Float.parse(place["latitude"] || ""),
         {lng, _} <- Float.parse(place["longitude"] || "") do
      {:ok, %{lat: lat, lng: lng, place: describe(place)}}
    else
      _ -> {:error, :unparseable}
    end
  end

  # A code with no places is as useless as one that doesn't exist.
  defp parse(_body), do: {:error, :not_found}

  defp describe(place) do
    [place["place name"], place["state"]]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(", ")
  end
end
