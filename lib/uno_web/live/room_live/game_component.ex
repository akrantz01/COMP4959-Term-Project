defmodule UnoWeb.RoomLive.GameComponent do
  use UnoWeb, :live_component

  attr :player_id, :string, required: true

  def mount(socket), do: {:ok, socket}

  def update(%{player_id: player_id}, socket) do
    {:ok, assign(socket, :player_id, player_id)}
  end
end
