defmodule UnoWeb.RoomLive do
  use UnoWeb, :live_view

  def mount(%{"room_id" => room_id}, session, socket) do
    player_id = session["player_id"] || Nanoid.generate()
    player_name = "Player-" <> String.slice(player_id, 0, 4)

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Uno.PubSub, "room:#{room_id}")
    end

    {:ok, room_state} = Uno.Room.join(room_id, player_id, player_name)
    {:ok, assign_from_state(socket, room_state, player_id, room_id)}
  end

  def terminate(_reason, socket) do
    Uno.Room.leave(socket.assigns.room_id, socket.assigns.player_id)
    :ok
  end

  def handle_info({:room_updated, room_state}, socket) do
    {:noreply,
     assign_from_state(
       socket,
       room_state,
       socket.assigns.player_id,
       socket.assigns.room_id
     )}
  end

  def handle_event("update_name", %{"player_name" => player_name}, socket) do
    Uno.Room.rename_player(
      socket.assigns.room_id,
      socket.assigns.player_id,
      player_name
    )

    {:noreply, socket}
  end

  def handle_event("start_game", _, socket) do
    Uno.Room.start_game(
      socket.assigns.room_id,
      socket.assigns.player_id
    )

    {:noreply, socket}
  end

  defp assign_from_state(socket, room_state, player_id, room_id) do
    players =
      room_state.players
      |> Enum.sort_by(& &1.name)

    current_player =
      Enum.find(players, fn p -> p.id == player_id end)

    assign(socket,
      room_id: room_id,
      player_id: player_id,
      player_name: (current_player && current_player.name) || "Player",
      players: players,
      status: room_state.status,
      is_admin: room_state.admin_player_id == player_id,
      last_winner_player_id: room_state.last_winner_player_id
    )
  end
end
