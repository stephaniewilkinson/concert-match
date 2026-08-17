defmodule ConcertMatch.Geocoding do
  @moduledoc """
  Turning a postal code into coordinates.

  Behind a behaviour for the same reason event sources are: this is a free
  third-party service with no contract, and if it stops answering the fix
  should be a new module rather than surgery on the settings page.

  Geocoding happens once, when someone saves a postal code — postal codes
  don't move, so the result is stored on the user and never looked up again
  unless they change it.
  """

  @type place :: %{
          lat: float(),
          lng: float(),
          # Human-readable, e.g. "Portland, Oregon". Shown back to the user so
          # a typo that happens to resolve somewhere real is still visible.
          place: String.t()
        }

  @doc """
  Resolve a postal code, or say why it couldn't be.

  `:not_found` means the code doesn't exist and the user should fix it.
  Anything else is the service failing, which is not the user's fault and
  should be reported differently.
  """
  @callback lookup(postal_code :: String.t(), country :: String.t()) ::
              {:ok, place()} | {:error, :not_found | term()}

  @doc """
  Look up a postal code with the configured geocoder.
  """
  @spec lookup(String.t(), String.t()) :: {:ok, place()} | {:error, :not_found | term()}
  def lookup(postal_code, country \\ "us") do
    impl().lookup(postal_code, country)
  end

  defp impl do
    Application.get_env(:concert_match, :geocoder, ConcertMatch.Geocoding.Zippopotam)
  end
end
