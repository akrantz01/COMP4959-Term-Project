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

  # --- Private UI helpers ---

  defp flatten_hand(hand),
    do:
      Enum.filter(hand, fn {_, count} -> count > 0 end)
      |> Enum.sort_by(fn {card, _} -> card_order(card) end)

  defp card_order(:wild), do: 0
  defp card_order(:wild_draw_4), do: 1

  defp card_order({colour, type}),
    do: card_order_colour(colour) + card_order_type(type)

  defp card_order_colour(:red), do: 100
  defp card_order_colour(:yellow), do: 200
  defp card_order_colour(:green), do: 300
  defp card_order_colour(:blue), do: 400

  defp card_order_type(n) when is_integer(n) and n in 0..9, do: n
  defp card_order_type(:skip), do: 10
  defp card_order_type(:reverse), do: 11
  defp card_order_type(:draw_2), do: 12
end
