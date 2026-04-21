defmodule UnoWeb.RoomLive do
  use UnoWeb, :live_view

  alias Uno.{Events, PubSub, Room}
  alias UnoWeb.RoomLive.{GameComponent, LobbyComponent}

  def mount(%{"room_id" => room_id}, %{"player_id" => player_id}, socket) do
    snapshot =
      if connected?(socket) do
        {:ok, snapshot} = Room.join(room_id, player_id)
        PubSub.subscribe({:room, room_id})
        PubSub.subscribe({:game, room_id})
        snapshot
      else
        %{state: :loading, players: []}
      end

    {:ok,
     socket
     |> assign(room_id: room_id, player_id: player_id)
     |> assign(snapshot)}
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

  def handle_info({:put_flash, kind, msg}, socket),
    do: {:noreply, put_flash(socket, kind, msg)}

  def handle_info(%mod{} = msg, socket) when is_map_key(@forwarded_events, mod) do
    with {component, id} <- component_target(socket.assigns.state, @forwarded_events[mod]) do
      send_update(component, id: id, event: msg)
    end

    {:noreply, socket}
  end

  defp component_target(state, :both), do: component_target(state, state)
  defp component_target(:lobby, :room), do: {LobbyComponent, "lobby"}
  defp component_target(:game, :game), do: {GameComponent, "game"}
  defp component_target(_state, _spec), do: nil
end
