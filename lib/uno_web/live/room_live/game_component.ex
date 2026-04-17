defmodule UnoWeb.RoomLive.GameComponent do
  use UnoWeb, :live_component

  attr :player_id, :string, required: true

  def mount(socket),
    do:
      {:ok,
       assign(socket,
         sequence: 0,
         hand: %{},
         opponents: [],
         top_card: nil,
         direction: :ltr,
         vulnerable_player_id: nil,
         chain: nil
       )}

  def update(%{event: %Uno.Events.Sync{} = event}, %{assigns: %{player_id: player_id}} = socket) do
    hand = Map.fetch!(event.hands, player_id)

    players_before = Enum.take_while(event.players, fn {id, _} -> id != player_id end)

    players_after =
      Enum.drop_while(event.players, fn {id, _} -> id != player_id end) |> Enum.drop(1)

    {:ok,
     assign(socket,
       sequence: event.sequence,
       hand: hand,
       opponents:
         Enum.map(players_after ++ players_before, fn {id, name} ->
           %{
             id: id,
             name: name,
             cards: Map.get(event.hands, id, %{}) |> Map.values() |> Enum.sum()
           }
         end),
       top_card: event.top_card,
       direction: event.direction,
       vulnerable_player_id: event.vulnerable_player_id,
       chain: event.chain
     )}
  end

  def update(%{player_id: player_id}, socket) do
    {:ok, assign(socket, :player_id, player_id)}
  end
end
