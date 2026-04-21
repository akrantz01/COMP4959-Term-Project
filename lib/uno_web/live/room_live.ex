defmodule UnoWeb.RoomLive do
  use UnoWeb, :live_view

  alias Uno.{Events, PubSub, Room}
  alias UnoWeb.RoomLive.{GameComponent, LobbyComponent}

  def mount(%{"room_id" => room_id}, %{"player_id" => player_id}, socket) do
    {:ok,
     socket
     |> assign(room_id: room_id, player_id: player_id)
     |> connect_to_room()}
  end

  # --- Handle Pub/Sub events

  def handle_info(%Uno.Events.GameStarted{game_id: _game_id}, socket) do
    {:noreply, assign(socket, state: :game)}
  end

  def handle_info(%Uno.Events.GameEnded{winner_id: _winner_id}, socket) do
    {:noreply, assign(socket, state: :lobby)}
  end

  @forwarded_events %{
    Events.PlayerJoined => :room,
    Events.PlayerLeft => :room,
    Events.AdminChanged => :room,
    Events.GameEnded => :room,
    Events.Sync => :game,
    Events.NextTurn => :game,
    Events.CardsPlayed => :game,
    Events.CardsDrawn => :game
  }

  def handle_info(%mod{} = msg, socket) when is_map_key(@forwarded_events, mod) do
    with {component, id} <- component_target(socket.assigns.state, @forwarded_events[mod]) do
      send_update(component, id: id, event: msg)
    end

    {:noreply, socket}
  end

  defp connect_to_room(%{assigns: %{room_id: room_id, player_id: player_id}} = socket) do
    if connected?(socket) do
      case join_room(room_id, player_id) do
        {:ok, snapshot} ->
          PubSub.subscribe({:room, room_id})
          PubSub.subscribe({:game, room_id})
          assign(socket, snapshot)

        {:error, :not_found} ->
          socket |> put_flash(:error, "Room not found!") |> redirect(to: "/")

        {:error, :room_not_in_lobby} ->
          socket |> put_flash(:error, "Game has already started!") |> redirect(to: "/")
      end
    else
      assign(socket, state: :loading, players: [])
    end
  end

  defp join_room(room_id, player_id) do
    try do
      Room.join(room_id, player_id)
    catch
      :exit, {:noproc, _} -> {:error, :not_found}
    end
  end

  defp component_target(state, :both), do: component_target(state, state)
  defp component_target(:lobby, :room), do: {LobbyComponent, "lobby"}
  defp component_target(:game, :game), do: {GameComponent, "game"}
  defp component_target(_state, _spec), do: nil
end
