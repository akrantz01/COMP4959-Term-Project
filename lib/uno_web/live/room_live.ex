defmodule UnoWeb.RoomLive do
  use UnoWeb, :live_view

  alias Uno.{Events, PubSub}
  alias UnoWeb.Forms.RoomForm
  alias UnoWeb.RoomLive.{GameComponent, LobbyComponent}

  def mount(%{"room_id" => room_id}, %{"player_id" => player_id}, socket) do
    # TODO: remove once more is implemented in favour of room lookup
    if connected?(socket) do
      PubSub.subscribe({:room, room_id})
      PubSub.subscribe({:game, room_id})
    end

    {:ok,
     socket
     |> assign(
       room_id: room_id,
       player_id: player_id,
       state: :lobby
     )
     |> assign(:room_form, RoomForm.new(%{player_id: player_id, state: :lobby}))}
  end

  # --- Temporary, remove once more is implemented ---

  def handle_event("room-update", %{"room" => params}, socket) do
    changeset = RoomForm.changeset(params)

    case RoomForm.parse(changeset) do
      {:ok, data} ->
        {:noreply,
         assign(socket,
           player_id: data.player_id,
           state: data.state,
           room_form: RoomForm.to_form(%{changeset | action: :validate})
         )}

      {:error, changeset} ->
        {:noreply, assign(socket, room_form: RoomForm.to_form(changeset))}
    end
  end

  def handle_event("update_name", %{"player_name" => player_name}, socket) do
    _ = Uno.Room.name(socket.assigns.room_id, socket.assigns.player_id, player_name)
    {:noreply, socket}
  end

  def handle_event("start_game", _params, socket) do
    _ = Uno.Room.start(socket.assigns.room_id, socket.assigns.player_id)
    {:noreply, socket}
  end

  # --- end temporary ---

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

  defp component_target(state, :both), do: component_target(state, state)
  defp component_target(:lobby, :room), do: {LobbyComponent, "lobby"}
  defp component_target(:game, :game), do: {GameComponent, "game"}
  defp component_target(_state, _spec), do: nil
end
