defmodule Uno.Repo do
  use Ecto.Repo,
    otp_app: :uno,
    adapter: Ecto.Adapters.Postgres
end
