defmodule ConcertMatch.Events.Source do
  @moduledoc """
  What an event data source has to provide.

  There is exactly one implementation today — Ticketmaster — and this
  behaviour exists because of how the free concert-data market has gone.
  Bandsintown, which the 2016 version of this app used with a made-up
  `app_id`, is partner-only now and its old endpoint no longer resolves.
  Songkick requires a paid licence that explicitly excludes hobby projects.
  Ticketmaster is what's left, and its coverage skews to large rooms and
  Live Nation bookings — thinnest on exactly the small-club shows a taste
  matcher tends to surface.

  So when the unmatched-lineup log shows friends' bands playing venues
  Ticketmaster doesn't carry, a second source should be a new module rather
  than a rewrite of the matcher.

  Note that a second source means the same show can arrive twice, under two
  ids. Cross-source dedup (venue, date, and headliner is usually enough) is
  not built yet, deliberately — but `events.source` exists so it can be.
  """

  @typedoc """
  One concert, normalized. `source_event_id` need only be unique within the
  source; the database keys on the pair.
  """
  @type event :: %{
          required(:source) => String.t(),
          required(:source_event_id) => String.t(),
          required(:name) => String.t(),
          required(:artist_names) => [String.t()],
          optional(:starts_at) => DateTime.t() | nil,
          optional(:venue_name) => String.t() | nil,
          optional(:city) => String.t() | nil,
          optional(:lat) => float() | nil,
          optional(:lng) => float() | nil,
          optional(:url) => String.t() | nil,
          optional(:image_url) => String.t() | nil
        }

  @type area :: %{lat: float(), lng: float(), radius_miles: integer()}

  @doc "A short identifier stored on every event this source produces."
  @callback name() :: String.t()

  @doc """
  Every upcoming music event in the area.

  Implementations should page until exhausted or until the source's paging
  ceiling, and should not raise on an empty result.
  """
  @callback fetch_events(area()) :: {:ok, [event()]} | {:error, term()}
end
