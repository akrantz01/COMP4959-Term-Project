defmodule UnoWeb.RoomLive.LobbyComponent do
  use UnoWeb, :live_component

  def mount(socket), do: {:ok, assign(socket, :players, [])}

  def update(%{event: %Uno.Events.PlayerJoined{} = event}, socket) do
    {:ok, update(socket, :players, fn p -> Enum.uniq([event.player_id | p]) end)}
  end

  def update(%{event: %Uno.Events.PlayerLeft{} = event}, socket) do
    {:ok, update(socket, :players, fn p -> List.delete(p, event.player_id) end)}
  end

  # Assign directly passed in properties
  def update(%{id: _id}, socket), do: {:ok, socket}
end
