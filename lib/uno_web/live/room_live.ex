defmodule UnoWeb.RoomLive do
  use UnoWeb, :live_view

  # alias UnoWeb.RoomLive.{GameComponent, LobbyComponent}

  def mount(%{"room_id" => room_id}, _session, socket) do
    player_id = socket.assigns[:player_id] || Nanoid.generate()

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Uno.PubSub, "room:#{room_id}")
      Uno.Room.join(room_id, player_id)
    end

    {:ok,
     assign(socket,
       room_id: room_id,
       player_id: player_id,
       players: [],
       status: :waiting
     )}
  end

  def terminate(_reason, socket) do
    Uno.Room.leave(socket.assigns.room_id, socket.assigns.player_id)
    :ok
  end

  ## HANDLE PUBSUB EVENTS

  def handle_info({:player_joined, player_id}, socket) do
    {:noreply, update(socket, :players, fn p -> Enum.uniq([player_id | p]) end)}
  end

  def handle_info({:player_left, player_id}, socket) do
    {:noreply, update(socket, :players, fn p -> List.delete(p, player_id) end)}
  end

  def handle_info({:game_started, _}, socket) do
    {:noreply, assign(socket, status: :playing)}
  end

  def handle_info({:game_ended, _}, socket) do
    {:noreply, assign(socket, status: :ended)}
  end

  ## UI EVENTS

  def handle_event("start_game", _, socket) do
    Uno.Room.start_game(socket.assigns.room_id)
    {:noreply, socket}
  end

  def handle_event("end_game", _, socket) do
    Uno.Room.end_game(socket.assigns.room_id)
    {:noreply, socket}
  end
end
