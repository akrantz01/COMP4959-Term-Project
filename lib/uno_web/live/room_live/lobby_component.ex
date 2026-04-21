defmodule UnoWeb.RoomLive.LobbyComponent do
  use UnoWeb, :live_component

  alias Uno.Events

  def mount(socket) do
    {:ok,
     socket
     |> assign(:room_id, nil)
     |> assign(:player_id, nil)
     |> assign(:player_name, "")
     |> stream(:players, [], reset: true)
     |> assign(:connected_count, 0)
     |> assign(:is_admin, false)
     |> assign(:last_winner_player_id, nil)}
  end

  def update(%{event: %Events.PlayerJoined{} = event}, socket) do
    {:ok,
     socket
     |> update(:connected_count, &(&1 + 1))
     |> maybe_update_player_name(event)
     |> stream_insert(:players, %{
       id: event.player_id,
       name: event.name,
       connected: true,
       wins: 0,
       losses: 0
     })}
  end

  def update(%{event: %Events.PlayerLeft{} = event}, socket) do
    {:ok,
     socket
     |> update(:connected_count, &(&1 - 1))
     |> stream_delete(:players, %{id: event.player_id})}
  end

  def update(%{event: %Events.AdminChanged{new_admin_id: new_admin_id}}, socket) do
    {:ok, assign(socket, :is_admin, socket.assigns.player_id == new_admin_id)}
  end

  def update(%{event: %Events.GameEnded{winner_id: winner_id}}, socket) do
    {:ok, assign(socket, :last_winner_player_id, winner_id)}
  end

  def update(
        %{id: _id, room_id: room_id, player_id: player_id, players: players} = assigns,
        socket
      ) do
    socket =
      socket
      |> assign(assigns)
      |> assign(:room_id, room_id)
      |> assign(:player_id, player_id)
      |> assign(:connected_count, length(players))
      |> assign(
        :player_name,
        Enum.find_value(players, "", fn p -> if(p.id == player_id, do: p.name) end)
      )
      |> stream(:players, players, reset: true)

    {:ok, socket}
  end

  def update(%{id: _id} = assigns, socket) do
    {:ok, assign(socket, assigns)}
  end

  defp maybe_update_player_name(socket, %{player_id: player_id, name: name}) do
    update(socket, :player_name, fn previous_name ->
      if(player_id == socket.assigns.player_id, do: name, else: previous_name)
    end)
  end
end
