defmodule UnoWeb.RoomLive do
  use UnoWeb, :live_view

  alias Uno.{Events, PubSub}
  alias UnoWeb.RoomLive.{GameComponent, LobbyComponent}

  def mount(%{"id" => id}, _session, socket) do
    # TODO: remove once room and game exist
    PubSub.subscribe({:room, id})
    PubSub.subscribe({:game, id})

    {:ok, socket |> assign(:id, id) |> assign(:state, :lobby)}
  end

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
