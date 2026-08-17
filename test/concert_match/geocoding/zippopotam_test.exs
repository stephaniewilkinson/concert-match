defmodule ConcertMatch.Geocoding.ZippopotamTest do
  use ExUnit.Case, async: true

  alias ConcertMatch.Geocoding.Zippopotam

  # Recorded from api.zippopotam.us/us/97214.
  defp real_response do
    %{
      "country" => "United States",
      "country abbreviation" => "US",
      "post code" => "97214",
      "places" => [
        %{
          "place name" => "Portland",
          "longitude" => "-122.6364",
          "latitude" => "45.5142",
          "state" => "Oregon",
          "state abbreviation" => "OR"
        }
      ]
    }
  end

  test "resolves a postal code to coordinates and a place name" do
    Req.Test.stub(Zippopotam, fn conn -> Req.Test.json(conn, real_response()) end)

    assert {:ok, place} = Zippopotam.lookup("97214", "us")

    assert_in_delta place.lat, 45.5142, 0.0001
    assert_in_delta place.lng, -122.6364, 0.0001
    assert place.place == "Portland, Oregon"
  end

  test "requests the country and code in the path" do
    Req.Test.stub(Zippopotam, fn conn ->
      assert conn.request_path == "/us/97214"
      Req.Test.json(conn, real_response())
    end)

    assert {:ok, _} = Zippopotam.lookup("97214", "US")
  end

  test "reports an unknown code as :not_found" do
    Req.Test.stub(Zippopotam, fn conn ->
      conn |> Plug.Conn.put_status(404) |> Req.Test.json(%{})
    end)

    # Distinct from a service failure, because only one of the two is
    # something the user can fix.
    assert {:error, :not_found} = Zippopotam.lookup("00000", "us")
  end

  test "treats a code with no places as not found" do
    Req.Test.stub(Zippopotam, fn conn -> Req.Test.json(conn, %{"places" => []}) end)

    assert {:error, :not_found} = Zippopotam.lookup("12345", "us")
  end

  test "reports a service failure separately" do
    Req.Test.stub(Zippopotam, fn conn ->
      conn |> Plug.Conn.put_status(503) |> Req.Test.json(%{})
    end)

    assert {:error, {:http_error, 503}} = Zippopotam.lookup("97214", "us")
  end

  test "survives coordinates it can't parse" do
    Req.Test.stub(Zippopotam, fn conn ->
      Req.Test.json(conn, %{
        "places" => [%{"place name" => "Nowhere", "latitude" => "", "longitude" => ""}]
      })
    end)

    assert {:error, :unparseable} = Zippopotam.lookup("97214", "us")
  end

  test "handles a place with no state" do
    Req.Test.stub(Zippopotam, fn conn ->
      Req.Test.json(conn, %{
        "places" => [%{"place name" => "Monaco", "latitude" => "43.7", "longitude" => "7.4"}]
      })
    end)

    assert {:ok, %{place: "Monaco"}} = Zippopotam.lookup("98000", "mc")
  end
end
