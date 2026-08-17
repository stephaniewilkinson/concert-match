defmodule ConcertMatchWeb.DataLive do
  @moduledoc """
  Everything Concert Match holds about the person looking at it.

  Deliberately complete rather than flattering: if the matching produces
  something odd, this is the page that explains why, and the answer is usually
  visible in the artist list.

  Tokens are the one exception. Their presence and expiry are shown because
  that's what breaks; the values themselves are not, since a page that prints
  a live Spotify credential is a page that leaks one over anybody's shoulder.
  """

  use ConcertMatchWeb, :live_view

  alias ConcertMatch.Accounts
  alias ConcertMatch.Events
  alias ConcertMatch.Music
  alias ConcertMatch.Notifications

  @per_page 100

  @source_labels %{
    "top_short" => "Top, last 4 weeks",
    "top_medium" => "Top, last 6 months",
    "top_long" => "Top, last year",
    "library" => "Saved library"
  }

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "Your data")
     |> assign(search: "", source: "all", page: 1)
     |> assign(source_labels_list: Enum.sort_by(@source_labels, fn {key, _} -> key end))
     |> load_data()}
  end

  @impl true
  def handle_event("filter", %{"search" => search, "source" => source}, socket) do
    {:noreply,
     socket
     |> assign(search: search, source: source, page: 1)
     |> load_data()}
  end

  def handle_event("page", %{"to" => to}, socket) do
    {:noreply, socket |> assign(page: String.to_integer(to)) |> load_data()}
  end

  defp load_data(socket) do
    user = socket.assigns.current_user

    taste =
      Music.taste_for_user(user, search: socket.assigns.search, source: socket.assigns.source)

    total = length(taste)
    pages = max(1, ceil(total / @per_page))
    page = min(socket.assigns.page, pages)

    socket
    |> assign(summary: Music.taste_summary(user))
    |> assign(taste: Enum.slice(taste, (page - 1) * @per_page, @per_page))
    |> assign(matching_total: total, pages: pages, page: page)
    |> assign(matches: Events.matches_for_user(user.id))
    |> assign(sent: Notifications.sent_history(user))
    |> assign(friends: Enum.reject(Accounts.list_users(), &(&1.id == user.id)))
  end

  defp source_label(source), do: Map.get(@source_labels, source, source)

  defp format(nil), do: "—"
  defp format(%DateTime{} = at), do: Calendar.strftime(at, "%-d %b %Y at %H:%M UTC")
  defp format(value), do: to_string(value)

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div class="space-y-10">
        <header>
          <h1 class="text-2xl font-bold">Your data</h1>
          <p class="text-sm opacity-70">
            Everything Concert Match has stored about you, and where it came from.
          </p>
        </header>

        <section class="space-y-3">
          <h2 class="text-lg font-semibold">Your account</h2>
          <dl class="grid grid-cols-1 gap-x-8 gap-y-2 sm:grid-cols-2">
            <.field label="Spotify ID" value={@current_user.spotify_id} />
            <.field label="Display name" value={@current_user.display_name} />
            <.field label="Email for digests" value={@current_user.email} />
            <.field
              label="Location"
              value={location_line(@current_user)}
            />
            <.field label="Search radius" value={"#{@current_user.radius_miles} miles"} />
            <.field
              label="Coordinates"
              value={coordinate_line(@current_user)}
            />
            <.field
              label="Digest emails"
              value={if @current_user.notify_enabled, do: "On", else: "Off"}
            />
            <.field label="Account created" value={format(@current_user.inserted_at)} />
          </dl>
          <p class="text-xs opacity-50">
            Your Spotify tokens are stored so imports can run overnight without you.
            They aren't shown here. The current one expires {format(@current_user.token_expires_at)}.
          </p>
        </section>

        <section class="space-y-3">
          <h2 class="text-lg font-semibold">What we imported</h2>
          <p :if={@summary.total_rows == 0} class="opacity-70">
            Nothing yet. <.link navigate={~p"/home"} class="link">Import your music</.link>.
          </p>
          <div :if={@summary.total_rows > 0} class="space-y-2">
            <p class="opacity-80">
              {@summary.distinct_artists} artists, from {@summary.total_rows} signals.
              Last imported {format(@summary.last_imported_at)}.
            </p>
            <ul class="flex flex-wrap gap-2">
              <li :for={{source, count} <- Enum.sort(@summary.by_source)} class="badge badge-outline">
                {source_label(source)}: {count}
              </li>
            </ul>
          </div>
        </section>

        <section :if={@summary.total_rows > 0} class="space-y-3">
          <h2 class="text-lg font-semibold">Your artists</h2>
          <p class="text-sm opacity-60">
            Ordered by affinity, which decides what leads a digest. It never decides
            whether something matches — any overlap with a friend counts.
          </p>

          <form id="taste-filter" phx-change="filter" class="flex flex-wrap gap-3 items-end">
            <input
              type="search"
              name="search"
              value={@search}
              placeholder="Search artists"
              class="input input-bordered"
            />
            <select name="source" class="select select-bordered">
              <option value="all" selected={@source == "all"}>Every source</option>
              <option :for={{key, label} <- @source_labels_list} value={key} selected={@source == key}>
                {label}
              </option>
            </select>
          </form>

          <p class="text-sm opacity-60">
            {@matching_total} {if @matching_total == 1, do: "artist", else: "artists"} shown.
          </p>

          <div class="overflow-x-auto">
            <table class="table table-sm">
              <thead>
                <tr>
                  <th>Artist</th>
                  <th>Best rank</th>
                  <th>Where it came from</th>
                  <th class="text-right">Affinity</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={row <- @taste}>
                  <td class="font-medium">{row.artist.name}</td>
                  <td>{if row.best_rank, do: "##{row.best_rank}", else: "—"}</td>
                  <td class="text-sm opacity-70">
                    {Enum.map_join(row.sources, ", ", &source_label/1)}
                  </td>
                  <td class="text-right tabular-nums">{row.score}</td>
                </tr>
              </tbody>
            </table>
          </div>

          <div :if={@pages > 1} class="flex items-center gap-2">
            <button
              :if={@page > 1}
              phx-click="page"
              phx-value-to={@page - 1}
              class="btn btn-sm"
            >
              Previous
            </button>
            <span class="text-sm opacity-60">Page {@page} of {@pages}</span>
            <button
              :if={@page < @pages}
              phx-click="page"
              phx-value-to={@page + 1}
              class="btn btn-sm"
            >
              Next
            </button>
          </div>
        </section>

        <section class="space-y-3">
          <h2 class="text-lg font-semibold">Shows you match</h2>
          <p class="opacity-70">
            {length(@matches.shared)} shared with a friend, {length(@matches.solo)} just you.
          </p>
        </section>

        <section class="space-y-3">
          <h2 class="text-lg font-semibold">Emails we've sent you</h2>
          <p :if={@sent == []} class="opacity-70">None yet.</p>
          <ul :if={@sent != []} class="space-y-1">
            <li :for={entry <- @sent} class="text-sm">
              <span class="opacity-60">{format(entry.sent_at)}</span> — {entry.event.name}
            </li>
          </ul>
        </section>

        <section class="space-y-3">
          <h2 class="text-lg font-semibold">Who you're matched against</h2>
          <p :if={@friends == []} class="opacity-70">
            Nobody else has logged in yet, so nothing can be shared.
          </p>
          <ul :if={@friends != []} class="flex flex-wrap gap-2">
            <li :for={friend <- @friends} class="badge badge-outline">
              {friend.display_name || "Someone"}
            </li>
          </ul>
          <p class="text-xs opacity-50">
            Spotify allows five people on an app like this one, so this list can never
            be longer than four.
          </p>
        </section>
      </div>
    </Layouts.app>
    """
  end

  attr :label, :string, required: true
  attr :value, :string, default: nil

  defp field(assigns) do
    ~H"""
    <div class="border-b border-base-200 py-1">
      <dt class="text-xs uppercase tracking-wide opacity-50">{@label}</dt>
      <dd class="font-medium">{@value || "—"}</dd>
    </div>
    """
  end

  defp location_line(%{postal_code: nil}), do: nil

  defp location_line(user) do
    [user.postal_code, user.postal_place, String.upcase(user.country || "")]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(" · ")
  end

  defp coordinate_line(%{home_lat: nil}), do: nil

  defp coordinate_line(user) do
    "#{Float.round(user.home_lat, 4)}, #{Float.round(user.home_lng, 4)}"
  end
end
