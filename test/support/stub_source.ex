defmodule ConcertMatch.StubSource do
  @moduledoc """
  An `Events.Source` that returns whatever the test puts in it.

  Stored in the process dictionary so tests stay `async: true`.
  """

  @behaviour ConcertMatch.Events.Source

  @key :stub_source_response

  @impl true
  def name, do: "stub"

  @impl true
  def fetch_events(_area) do
    case Process.get(@key, {:ok, []}) do
      {:error, reason} -> {:error, reason}
      {:ok, events} -> {:ok, events}
    end
  end

  def put_events(events), do: Process.put(@key, {:ok, events})

  def put_error(reason), do: Process.put(@key, {:error, reason})
end
