defmodule UnoWeb.Plugs.AssignPlayerId do
  @moduledoc """
  Assign a player id in cookie and session.
  """

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    player_id = conn.cookies["player_id"] || Nanoid.generate()

    conn
    |> fetch_session()
    |> put_resp_cookie("player_id", player_id, http_only: true)
    |> put_session(:player_id, player_id)
    |> assign(:player_id, player_id)
  end
end
