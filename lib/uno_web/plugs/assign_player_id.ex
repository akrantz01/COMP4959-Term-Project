defmodule UnoWeb.Plugs.AssignPlayerId do
  @moduledoc """
  Assign a player id in cookie and session.
  """

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    player_id =
      get_session(conn, "player_id") ||
        Nanoid.generate()

    conn
    |> put_session("player_id", player_id)
    |> assign(:player_id, player_id)
  end
end
