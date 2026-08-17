defmodule ConcertMatchWeb.HomeLive do
  @moduledoc """
  Upcoming shows that match you, with whoever else is into them.
  """

  use ConcertMatchWeb, :live_view

  alias ConcertMatch.Accounts
  alias ConcertMatch.Events
  alias ConcertMatch.Music
  alias ConcertMatch.Workers.RefreshTasteWorker

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    if connected?(socket) do
      Phoenix.PubSub.subscribe(ConcertMatch.PubSub, RefreshTasteWorker.topic(user.id))
    end

    {:ok,
     socket
     |> assign(page_title: "Your matches")
     |> assign(importing?: RefreshTasteWorker.in_progress?(user.id))
     |> assign(names: display_names())
     |> load_matches()}
  end

  @impl true
  def handle_event("import_music", _params, socket) do
    case RefreshTasteWorker.enqueue(socket.assigns.current_user.id) do
      {:ok, :queued} ->
        {:noreply, assign(socket, importing?: true)}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Couldn't start the import. Try again in a moment.")}
    end
  end

  @impl true
  def handle_info({:taste_refreshed, count}, socket) do
    {:noreply,
     socket
     |> assign(importing?: false)
     |> load_matches()
     |> put_flash(:info, "Imported #{count} #{pluralize(count, "artist")} from Spotify.")}
  end

  def handle_info({:taste_failed, :no_refresh_token}, socket) do
    {:noreply,
     socket
     |> assign(importing?: false)
     |> put_flash(:error, "Spotify needs you to log in again. Log out and back in.")}
  end

  def handle_info({:taste_failed, _reason}, socket) do
    {:noreply,
     socket
     |> assign(importing?: false)
     |> put_flash(:error, "Spotify wouldn't answer. It'll retry on its own shortly.")}
  end

  defp load_matches(socket) do
    user = socket.assigns.current_user
    matches = Events.matches_for_user(user.id)

    socket
    |> assign(shared: matches.shared, solo: matches.solo)
    |> assign(artists: Music.top_artists_for_user(user, 12))
  end

  # Five users at most, so loading every name is cheaper than joining.
  defp display_names do
    Accounts.list_users() |> Map.new(&{&1.id, &1.display_name || "Someone"})
  end

  defp pluralize(1, word), do: word
  defp pluralize(_, word), do: word <> "s"

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
          <div class="flex-1">
            <h1 class="text-2xl font-bold">
              {@current_user.display_name || "Your matches"}
            </h1>
            <p :if={@current_user.home_lat} class="text-sm opacity-60">
              Within {@current_user.radius_miles} miles of home
            </p>
            <p :if={is_nil(@current_user.home_lat)} class="text-sm opacity-60">
              <.link navigate={~p"/settings"} class="link">Set your location</.link> to start matching
            </p>
          </div>
          <.import_button :if={@artists != []} importing?={@importing?} class="btn-ghost btn-sm" />
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

        <section :if={@artists == []} class="card bg-base-200">
          <div class="card-body items-start gap-4">
            <div>
              <h2 class="card-title">Import your listening</h2>
              <p class="opacity-80">
                Concert Match needs to know what you listen to before it can match you
                with anyone. This reads your top artists, the artists you follow, and
                your saved library from Spotify.
              </p>
              <p :if={@importing?} class="mt-2 text-sm opacity-60">
                This can take a minute if your library is large. You can leave the page;
                it'll keep going.
              </p>
            </div>
            <.import_button importing?={@importing?} class="btn-primary" />
          </div>
        </section>

        <section :if={@artists != [] and @shared == [] and @solo == []} class="card bg-base-200">
          <div class="card-body">
            <p>
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

  attr :importing?, :boolean, required: true
  attr :class, :string, default: ""

  defp import_button(assigns) do
    ~H"""
    <button
      type="button"
      phx-click="import_music"
      phx-disable-with="Importing…"
      disabled={@importing?}
      class={["btn", @class]}
    >
      {if @importing?, do: "Importing…", else: "Import my music"}
    </button>
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
