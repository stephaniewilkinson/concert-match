defmodule ConcertMatch.Repo do
  use Ecto.Repo,
    otp_app: :concert_match,
    adapter: Ecto.Adapters.Postgres
end
