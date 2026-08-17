defmodule ConcertMatchWeb.SettingsLive do
  @moduledoc """
  Where you live, how far you'll travel, and whether to email you.

  The postal code is load-bearing: event sweeps are driven by the distinct set
  of user locations, so a user without one matches nothing.
  """

  use ConcertMatchWeb, :live_view

  alias ConcertMatch.Accounts
  alias ConcertMatch.Geocoding

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
         |> put_flash(:info, saved_message(user))}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  # Naming the place the postal code resolved to is the confirmation that it
  # went somewhere sensible. "Saved" alone would hide a typo that happens to
  # be a real code in another state.
  defp saved_message(%{postal_place: nil}), do: "Settings saved."

  defp saved_message(%{postal_place: place}),
    do: "Settings saved. Looking for shows near #{place}."

  defp assign_form(socket, changeset) do
    assign(socket, :form, to_form(changeset, as: "user"))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div class="space-y-6">
        <h1 class="text-2xl font-bold">Settings</h1>

        <.form
          for={@form}
          id="settings-form"
          phx-change="validate"
          phx-submit="save"
          class="space-y-6"
        >
          <fieldset class="space-y-2">
            <legend class="font-semibold">Where to email you</legend>
            <.input field={@form[:email]} type="email" label="Email address" />
            <p class="text-sm opacity-60">
              Taken from your Spotify account to begin with. Changing it here sticks —
              logging in again won't overwrite it.
            </p>
          </fieldset>

          <fieldset class="space-y-2">
            <legend class="font-semibold">Where you're looking for shows</legend>

            <div class="grid grid-cols-3 gap-4">
              <.input
                field={@form[:country]}
                type="select"
                label="Country"
                options={Geocoding.countries()}
              />
              <.input field={@form[:postal_code]} type="text" label="Postal code" />
              <.input field={@form[:radius_miles]} type="number" label="Within (miles)" />
            </div>

            <p :if={@current_user.postal_place} class="text-sm opacity-60">
              Currently searching near {@current_user.postal_place}.
            </p>
          </fieldset>

          <fieldset>
            <.input
              field={@form[:notify_enabled]}
              type="checkbox"
              label="Email me when a show matches me and a friend"
            />
          </fieldset>

          <button type="submit" phx-disable-with="Saving…" class="btn btn-primary">Save</button>
        </.form>
      </div>
    </Layouts.app>
    """
  end
end
