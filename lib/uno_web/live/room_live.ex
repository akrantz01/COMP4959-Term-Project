defmodule UnoWeb.RoomLive do
  use UnoWeb, :live_view

  alias UnoWeb.RoomLive.{GameComponent, LobbyComponent}

  def mount(%{"id" => id}, _session, socket) do
    # TODO: remove once room and game exist
    PubSub.subscribe({:room, id})
    PubSub.subscribe({:game, id})

    {:ok, socket |> assign(:id, id) |> assign(:state, :lobby)}
  end
end
