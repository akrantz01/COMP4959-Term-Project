defmodule UnoWeb.Plugs.AssignPlayerId do
  @moduledoc """
  assign an player id in cookie
  """
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    player_id = conn.cookies["player_id"] || Nanoid.generate()

    conn
    |> put_resp_cookie("player_id", player_id, http_only: true)
    |> assign(:player_id, player_id)
  end
end
