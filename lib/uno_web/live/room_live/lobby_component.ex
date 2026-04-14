defmodule UnoWeb.RoomLive.LobbyComponent do
  use UnoWeb, :live_component

  def update(assigns, socket) do
    connected_count = Enum.count(assigns.players, & &1.connected)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:connected_count, connected_count)}
  end
end
