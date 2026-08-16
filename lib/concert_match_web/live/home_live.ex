defmodule ConcertMatchWeb.HomeLive do
  @moduledoc """
  Your upcoming matched shows.

  Currently a stub confirming who you're logged in as; the overlap view lands
  once taste and events are being ingested.
  """

  use ConcertMatchWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Your matches")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div class="space-y-6">
        <div class="flex items-center gap-4">
          <img
            :if={@current_user.avatar_url}
            src={@current_user.avatar_url}
            alt=""
            class="size-14 rounded-full"
          />
          <div>
            <h1 class="text-2xl font-bold">
              {@current_user.display_name || "Logged in"}
            </h1>
            <p class="text-sm opacity-60">{@current_user.email}</p>
          </div>
        </div>

        <div class="card bg-base-200">
          <div class="card-body">
            <p>
              You're logged in with Spotify. Your listening history hasn't been
              imported yet, so there's nothing to match against.
            </p>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
