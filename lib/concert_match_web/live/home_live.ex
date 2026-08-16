defmodule ConcertMatchWeb.HomeLive do
  @moduledoc """
  Upcoming shows that match you, with whoever else is into them.
  """

  use ConcertMatchWeb, :live_view

  alias ConcertMatch.Accounts
  alias ConcertMatch.Events
  alias ConcertMatch.Music

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    matches = Events.matches_for_user(user.id)

    {:ok,
     socket
     |> assign(page_title: "Your matches")
     |> assign(shared: matches.shared, solo: matches.solo)
     |> assign(names: display_names())
     |> assign(artists: Music.top_artists_for_user(user, 12))}
  end

  # Five users at most, so loading every name is cheaper than joining.
  defp display_names do
    Accounts.list_users() |> Map.new(&{&1.id, &1.display_name || "Someone"})
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div class="space-y-10">
        <header class="flex items-center gap-4">
          <img
            :if={@current_user.avatar_url}
            src={@current_user.avatar_url}
            alt=""
            class="size-14 rounded-full"
          />
          <div>
            <h1 class="text-2xl font-bold">
              {@current_user.display_name || "Your matches"}
            </h1>
            <p :if={@current_user.home_lat} class="text-sm opacity-60">
              Within {@current_user.radius_miles} miles of home
            </p>
            <p :if={is_nil(@current_user.home_lat)} class="text-sm opacity-60">
              <.link navigate={~p"/settings"} class="link">
                Set your location
              </.link>
              to start matching
            </p>
          </div>
        </header>

        <section :if={@shared != []} class="space-y-4">
          <h2 class="text-lg font-semibold">You and your friends</h2>
          <ul class="space-y-3">
            <.match :for={match <- @shared} match={match} me={@current_user.id} names={@names} />
          </ul>
        </section>

        <section :if={@solo != []} class="space-y-4">
          <h2 class="text-lg font-semibold">
            {if @shared == [], do: "Shows for you", else: "Just you, so far"}
          </h2>
          <ul class="space-y-3">
            <.match :for={match <- @solo} match={match} me={@current_user.id} names={@names} />
          </ul>
        </section>

        <section :if={@shared == [] and @solo == []} class="card bg-base-200">
          <div class="card-body">
            <p :if={@artists == []}>
              Your listening hasn't been imported yet. It runs overnight, or you can
              trigger it by hand with <code class="text-sm">ConcertMatch.Music.refresh_taste/1</code>.
            </p>
            <p :if={@artists != []}>
              Nothing upcoming matches you yet. Concert Match checks nightly and will
              email you when something turns up.
            </p>
          </div>
        </section>

        <section :if={@artists != []} class="space-y-4">
          <h2 class="text-lg font-semibold">What we're matching on</h2>
          <ul class="flex flex-wrap gap-2">
            <li :for={artist <- @artists} class="badge badge-lg badge-outline">
              {artist.name}
            </li>
          </ul>
        </section>
      </div>
    </Layouts.app>
    """
  end

  attr :match, :map, required: true
  attr :me, :integer, required: true
  attr :names, :map, required: true

  defp match(assigns) do
    ~H"""
    <li class="card bg-base-200">
      <div class="card-body gap-1">
        <div class="font-semibold">
          <.link :if={@match.event.url} href={@match.event.url} target="_blank" class="link">
            {@match.event.name}
          </.link>
          <span :if={is_nil(@match.event.url)}>{@match.event.name}</span>
        </div>
        <div class="text-sm opacity-70">{venue_line(@match.event)}</div>
        <div :if={others(@match, @me, @names) != []} class="text-sm">
          {others_sentence(others(@match, @me, @names))}
        </div>
      </div>
    </li>
    """
  end

  defp others(%{users: users}, me, names) do
    users
    |> Enum.reject(&(&1.user_id == me))
    |> Enum.map(&Map.get(names, &1.user_id, "Someone"))
  end

  defp others_sentence([one]), do: "#{one} is into this too"
  defp others_sentence(many), do: "#{Enum.join(many, ", ")} are into this too"

  defp venue_line(event) do
    [format_date(event.starts_at), event.venue_name, event.city]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" · ")
  end

  defp format_date(nil), do: nil
  defp format_date(datetime), do: Calendar.strftime(datetime, "%a %-d %b")
end
