defmodule ConcertMatchWeb.SettingsLive do
  @moduledoc """
  Where you live, how far you'll travel, and whether to email you.

  The home location is load-bearing: event sweeps are driven by the distinct
  set of user locations, so a user without one matches nothing.
  """

  use ConcertMatchWeb, :live_view

  alias ConcertMatch.Accounts

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "Settings")
     |> assign_form(Accounts.change_settings(socket.assigns.current_user))}
  end

  @impl true
  def handle_event("validate", %{"user" => params}, socket) do
    changeset =
      socket.assigns.current_user
      |> Accounts.change_settings(params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"user" => params}, socket) do
    case Accounts.update_settings(socket.assigns.current_user, params) do
      {:ok, user} ->
        {:noreply,
         socket
         |> assign(current_user: user)
         |> assign_form(Accounts.change_settings(user))
         |> put_flash(:info, "Settings saved.")}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  # Sent by the geolocation hook after the browser resolves coordinates.
  def handle_event("set_location", %{"lat" => lat, "lng" => lng}, socket) do
    params = %{"home_lat" => lat, "home_lng" => lng}

    changeset =
      socket.assigns.current_user
      |> Accounts.change_settings(params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  defp assign_form(socket, changeset) do
    assign(socket, :form, to_form(changeset, as: "user"))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div class="space-y-6">
        <h1 class="text-2xl font-bold">Settings</h1>

        <.form for={@form} phx-change="validate" phx-submit="save" class="space-y-6">
          <fieldset class="space-y-4">
            <legend class="font-semibold">Where you're looking for shows</legend>

            <div id="geolocate" phx-hook="Geolocate">
              <button type="button" class="btn btn-sm" phx-click={JS.dispatch("cm:geolocate")}>
                Use my current location
              </button>
            </div>

            <div class="grid grid-cols-2 gap-4">
              <.input field={@form[:home_lat]} type="number" step="any" label="Latitude" />
              <.input field={@form[:home_lng]} type="number" step="any" label="Longitude" />
            </div>

            <.input
              field={@form[:radius_miles]}
              type="number"
              label="Search radius (miles)"
            />
          </fieldset>

          <fieldset>
            <.input
              field={@form[:notify_enabled]}
              type="checkbox"
              label="Email me when a show matches me and a friend"
            />
          </fieldset>

          <button type="submit" class="btn btn-primary">Save</button>
        </.form>
      </div>
    </Layouts.app>
    """
  end
end
