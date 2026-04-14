defmodule UnoWeb.RoomLive do
  use UnoWeb, :live_view

  alias UnoWeb.RoomLive.{GameComponent, LobbyComponent}

  def mount(%{"id" => id}, _session, socket) do
    {:ok, socket |> assign(:id, id) |> assign(:state, :lobby)}
  end
end
