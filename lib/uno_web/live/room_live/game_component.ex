defmodule UnoWeb.RoomLive.GameComponent do
  use UnoWeb, :live_component

  alias UnoWeb.Forms.{Card, SelectedCard}

  attr :player_id, :string, required: true

  def mount(socket),
    do:
      {:ok,
       assign(socket,
         sequence: 0,
         hand: %{},
         opponents: [],
         top_card: nil,
         turn_player_id: nil,
         turn_skipped: false,
         direction: :ltr,
         vulnerable_player_id: nil,
         chain: nil,
         selected_cards: []
       )}

  def handle_event("toggle-card", params, %{assigns: %{selected_cards: selected_cards}} = socket) do
    with {:ok, selected} <- SelectedCard.parse(params),
         card = Card.format(:hand, selected.card),
         {:ok, new_cards} <- toggle_selected_card(selected_cards, {card, selected.index}) do
      {:noreply, assign(socket, :selected_cards, new_cards)}
    else
      {:error, :different_type} ->
        {:noreply, put_flash(socket, :error, "Selected cards must all be the same type")}

      {:error, :duplicate_colour} ->
        {:noreply, put_flash(socket, :error, "Selected cards must each be a different colour")}

      _ ->
        {:noreply, socket}
    end
  end

  def update(%{event: %Uno.Events.NextTurn{} = event}, socket) do
    # TODO: validate sequence number
    {:ok,
     assign(socket,
       sequence: event.sequence,
       turn_player_id: event.player_id,
       turn_skipped: event.skipped,
       top_card: event.top_card,
       direction: event.direction,
       vulnerable_player_id: event.vulnerable_player_id,
       chain: event.chain
     )}
  end

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
       turn_player_id: event.current_player_id,
       direction: event.direction,
       vulnerable_player_id: event.vulnerable_player_id,
       chain: event.chain
     )}
  end

  # Assign directly passed in properties
  def update(%{id: _id, player_id: player_id}, socket),
    do: {:ok, assign(socket, :player_id, player_id)}

  # --- Private UI helpers ---

  defp toggle_selected_card(selected_cards, {card, _} = indexed_card) do
    {colour, type} = card_parts(card)

    case toggle_selected_card(selected_cards, indexed_card, colour, type) do
      {:added, rest} -> {:ok, [indexed_card | rest]}
      {:removed, rest} -> {:ok, rest}
      error -> error
    end
  end

  defp toggle_selected_card([], _indexed_card, _colour, _type), do: {:added, []}

  defp toggle_selected_card([indexed_card | rest], indexed_card, _colour, _type),
    do: {:removed, rest}

  defp toggle_selected_card([{head_card, _} = head | rest], indexed_card, colour, type) do
    {head_colour, head_type} = card_parts(head_card)

    cond do
      type != head_type ->
        {:error, :different_type}

      colour != nil && colour == head_colour ->
        {:error, :duplicate_colour}

      true ->
        with {tag, new_rest} when tag in [:added, :removed] <-
               toggle_selected_card(rest, indexed_card, colour, type) do
          {tag, [head | new_rest]}
        end
    end
  end

  defp direction_icon(%{direction: direction} = assigns) do
    assigns =
      case direction do
        :ltr ->
          assign(assigns,
            icon: "fas-arrow-rotate-right",
            flip: "animate-[flip-ltr_250ms_ease-in-out]",
            animation_direction: "[animation-direction:normal]"
          )

        :rtl ->
          assign(assigns,
            icon: "fas-arrow-rotate-left",
            flip: "animate-[flip-rtl_250ms_ease-in-out]",
            animation_direction: "[animation-direction:reverse]"
          )
      end

    ~H"""
    <div class={["size-16", @flip]}>
      <.icon
        name={@icon}
        class={["size-full animate-[spin_5s_linear_infinite]", @animation_direction]}
      />
    </div>
    """
  end

  defp flatten_hand(hand),
    do:
      Enum.filter(hand, fn {_, count} -> count > 0 end)
      |> Enum.sort_by(fn {card, _} -> card_order(card) end)

  defp card_parts(:wild), do: {nil, :wild}
  defp card_parts(:wild_draw_4), do: {nil, :wild_draw_4}
  defp card_parts({colour, type}), do: {colour, type}

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
