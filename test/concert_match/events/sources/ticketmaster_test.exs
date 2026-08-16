defmodule ConcertMatch.Events.Sources.TicketmasterTest do
  use ExUnit.Case, async: true

  alias ConcertMatch.Events.Sources.Ticketmaster

  # Shaped after a real Discovery v2 `/events.json` entry. The point of testing
  # against this rather than a tidy map is that the nesting is where a field
  # rename would actually bite.
  defp discovery_event(overrides \\ %{}) do
    Map.merge(
      %{
        "id" => "G5vYZ9Wd1A2bK",
        "name" => "Radiohead",
        "url" => "https://www.ticketmaster.com/event/G5vYZ9Wd1A2bK",
        "images" => [
          %{"ratio" => "3_2", "width" => 640, "url" => "https://example.com/3x2.jpg"},
          %{"ratio" => "16_9", "width" => 1136, "url" => "https://example.com/wide.jpg"},
          %{"ratio" => "16_9", "width" => 205, "url" => "https://example.com/small.jpg"}
        ],
        "dates" => %{
          "start" => %{
            "localDate" => "2026-09-14",
            "localTime" => "20:00:00",
            "dateTime" => "2026-09-15T03:00:00Z"
          }
        },
        "_embedded" => %{
          "venues" => [
            %{
              "name" => "Crystal Ballroom",
              "city" => %{"name" => "Portland"},
              "location" => %{"latitude" => "45.5231", "longitude" => "-122.6765"}
            }
          ],
          "attractions" => [
            %{"id" => "K8vZ917", "name" => "Radiohead"},
            %{"id" => "K8vZ918", "name" => "Sigur Rós"}
          ]
        }
      },
      overrides
    )
  end

  describe "normalize_event/1" do
    test "maps the fields the app depends on" do
      normalized = Ticketmaster.normalize_event(discovery_event())

      assert normalized.source == "ticketmaster"
      assert normalized.source_event_id == "G5vYZ9Wd1A2bK"
      assert normalized.name == "Radiohead"
      assert normalized.venue_name == "Crystal Ballroom"
      assert normalized.city == "Portland"
      assert normalized.url == "https://www.ticketmaster.com/event/G5vYZ9Wd1A2bK"
    end

    test "takes the whole lineup, not just the headliner" do
      normalized = Ticketmaster.normalize_event(discovery_event())
      assert normalized.artist_names == ["Radiohead", "Sigur Rós"]
    end

    test "parses coordinates from Ticketmaster's strings" do
      normalized = Ticketmaster.normalize_event(discovery_event())

      assert_in_delta normalized.lat, 45.5231, 0.0001
      assert_in_delta normalized.lng, -122.6765, 0.0001
    end

    test "parses the UTC start time" do
      normalized = Ticketmaster.normalize_event(discovery_event())
      assert normalized.starts_at == ~U[2026-09-15 03:00:00Z]
    end

    test "picks the widest 16:9 image" do
      normalized = Ticketmaster.normalize_event(discovery_event())
      assert normalized.image_url == "https://example.com/wide.jpg"
    end
  end

  describe "normalize_event/1 on ragged payloads" do
    test "falls back to the event name when there are no attractions" do
      event =
        discovery_event(%{
          "name" => "Some Local Band",
          "_embedded" => %{"venues" => []}
        })

      # Small listings frequently carry no attractions, and the event name is
      # usually just the artist. Dropping these would lose exactly the
      # small-venue shows Ticketmaster is already weakest on.
      assert Ticketmaster.normalize_event(event).artist_names == ["Some Local Band"]
    end

    test "survives a missing venue" do
      event = discovery_event(%{"_embedded" => %{"attractions" => [%{"name" => "X"}]}})
      normalized = Ticketmaster.normalize_event(event)

      assert normalized.venue_name == nil
      assert normalized.city == nil
      assert normalized.lat == nil
    end

    test "survives a missing date" do
      event = discovery_event(%{"dates" => %{}})
      assert Ticketmaster.normalize_event(event).starts_at == nil
    end

    test "survives unparseable coordinates" do
      event =
        discovery_event(%{
          "_embedded" => %{
            "venues" => [%{"name" => "V", "location" => %{"latitude" => "", "longitude" => nil}}]
          }
        })

      normalized = Ticketmaster.normalize_event(event)
      assert normalized.lat == nil
      assert normalized.lng == nil
    end

    test "survives having no images" do
      event = discovery_event(%{"images" => []})
      assert Ticketmaster.normalize_event(event).image_url == nil
    end
  end

  describe "fetch_events/1" do
    test "pages until Ticketmaster says there are no more" do
      Req.Test.stub(Ticketmaster, fn conn ->
        conn = Plug.Conn.fetch_query_params(conn)
        page = String.to_integer(conn.query_params["page"])

        Req.Test.json(conn, %{
          "_embedded" => %{"events" => [discovery_event(%{"id" => "evt-#{page}"})]},
          "page" => %{"totalPages" => 3}
        })
      end)

      assert {:ok, events} =
               Ticketmaster.fetch_events(%{lat: 45.5, lng: -122.6, radius_miles: 50})

      assert length(events) == 3
      assert Enum.map(events, & &1.source_event_id) == ["evt-0", "evt-1", "evt-2"]
    end

    test "stops on an empty page" do
      Req.Test.stub(Ticketmaster, fn conn ->
        Req.Test.json(conn, %{"page" => %{"totalPages" => 0}})
      end)

      assert {:ok, []} = Ticketmaster.fetch_events(%{lat: 45.5, lng: -122.6, radius_miles: 50})
    end

    test "sends the parameters that keep the sweep cheap and relevant" do
      Req.Test.stub(Ticketmaster, fn conn ->
        conn = Plug.Conn.fetch_query_params(conn)
        params = conn.query_params

        assert params["latlong"] == "45.5,-122.6"
        assert params["radius"] == "50"
        assert params["unit"] == "miles"
        assert params["classificationName"] == "music"
        # Without this, Discovery cheerfully returns last year's shows.
        assert params["startDateTime"] =~ ~r/^\d{4}-\d{2}-\d{2}T/

        Req.Test.json(conn, %{"page" => %{"totalPages" => 0}})
      end)

      assert {:ok, []} = Ticketmaster.fetch_events(%{lat: 45.5, lng: -122.6, radius_miles: 50})
    end

    test "reports an API error rather than an empty result" do
      Req.Test.stub(Ticketmaster, fn conn ->
        conn |> Plug.Conn.put_status(401) |> Req.Test.json(%{"fault" => "bad key"})
      end)

      assert {:error, {:http_error, 401, _}} =
               Ticketmaster.fetch_events(%{lat: 45.5, lng: -122.6, radius_miles: 50})
    end
  end
end
