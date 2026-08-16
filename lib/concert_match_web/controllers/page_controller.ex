defmodule ConcertMatchWeb.PageController do
  use ConcertMatchWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
