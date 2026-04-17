defmodule UnoWeb.RoomLive do
  use UnoWeb, :live_view

  # alias UnoWeb.RoomLive.{GameComponent, LobbyComponent}

  def mount(%{"room_id" => room_id}, _session, socket) do
    player_id = socket.assigns[:player_id] || Nanoid.generate()

    if connected?(socket) do
      Uno.PubSub.subscribe({:room, room_id})
      Uno.PubSub.subscribe({:game, room_id})
    end

    {:ok,
     socket
     |> assign(
       room_id: room_id,
       player_id: player_id,
       players: [],
       status: :waiting
     )
     |> assign(
       :room_form,
       RoomForm.new(%{
         player_id: player_id,
         state: :lobby
       })
     )}
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
    alias Uno.{Events, PubSub}
    alias UnoWeb.Forms.RoomForm
    alias UnoWeb.RoomLive.{GameComponent, LobbyComponent}
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

  # --- end temporary ---

  @forwarded_events %{
    Events.PlayerJoined => :room,
    Events.PlayerLeft => :room,
    Events.GameStarted => :room,
    Events.GameEnded => :room,
    Events.Sync => :game,
    Events.NextTurn => :game,
    Events.CardsPlayed => :game,
    Events.CardsDrawn => :game
  }

  def handle_info(%mod{} = msg, socket) when is_map_key(@forwarded_events, mod) do
    with {component, id} <- component_target(socket.assigns.state, @forwarded_events[mod]),
         do: send_update(component, id: id, event: msg)

    {:noreply, socket}
  end

  defp component_target(state, :both), do: component_target(state, state)
  defp component_target(:room, :room), do: {RoomComponent, "lobby"}
  defp component_target(:game, :game), do: {GameComponent, "game"}
  defp component_target(_state, _spec), do: nil
end
