defmodule UnoWeb.RoomLive.LobbyComponent do
  use UnoWeb, :live_component

  alias Uno.Events

  def mount(socket) do
    {:ok,
     socket
     |> assign(:room_id, nil)
     |> assign(:player_id, nil)
     |> assign(:player_name, "")
     |> assign(:players, [])
     |> assign(:connected_count, 0)
     |> assign(:is_admin, false)
     |> assign(:last_winner_player_id, nil)}
  end

  def update(%{event: %Events.PlayerJoined{} = event}, socket) do
    players =
      socket.assigns.players
      |> upsert_player(%{
        id: event.player_id,
        name: event.name,
        connected: true,
        wins: 0,
        losses: 0
      })

    {:ok,
     socket
     |> assign(:players, players)
     |> assign(:connected_count, count_connected(players))
     |> maybe_update_player_name()}
  end

  def update(%{event: %Events.PlayerLeft{} = event}, socket) do
    players =
      Enum.map(socket.assigns.players, fn player ->
        if player.id == event.player_id do
          Map.put(player, :connected, false)
        else
          player
        end
      end)

    {:ok,
     socket
     |> assign(:players, players)
     |> assign(:connected_count, count_connected(players))
     |> maybe_update_player_name()}
  end

  def update(%{event: %Events.AdminChanged{new_admin_id: new_admin_id}}, socket) do
    {:ok, assign(socket, :is_admin, socket.assigns.player_id == new_admin_id)}
  end

  def update(%{event: %Events.GameEnded{winner_id: winner_id}}, socket) do
    {:ok, assign(socket, :last_winner_player_id, winner_id)}
  end

  def update(%{id: _id, room_id: room_id, player_id: player_id} = assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign(:room_id, room_id)
      |> assign(:player_id, player_id)
      |> maybe_update_player_name()

    {:ok, socket}
  end

  def update(%{id: _id} = assigns, socket) do
    {:ok, assign(socket, assigns)}
  end

  defp upsert_player(players, incoming) do
    case Enum.find_index(players, &(&1.id == incoming.id)) do
      nil ->
        players ++ [incoming]

      index ->
        List.replace_at(players, index, Map.merge(Enum.at(players, index), incoming))
    end
  end

  defp count_connected(players) do
    Enum.count(players, &Map.get(&1, :connected, false))
  end

  defp maybe_update_player_name(socket) do
    player_name =
      socket.assigns.players
      |> Enum.find(fn p -> p.id == socket.assigns.player_id end)
      |> case do
        nil -> socket.assigns.player_name
        player -> player.name
      end

    assign(socket, :player_name, player_name)
  end
end
