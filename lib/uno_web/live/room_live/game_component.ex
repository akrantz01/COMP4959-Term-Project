defmodule UnoWeb.RoomLive.GameComponent do
  use UnoWeb, :live_component

  alias UnoWeb.Forms.{Card, SelectedCard}

  attr :player_id, :string, required: true

  def mount(socket),
    do:
      {:ok,
       socket
       |> assign(
         sequence: 0,
         hand: %{},
         opponents: [],
         top_card: nil,
         turn_player_id: nil,
         turn_skipped: false,
         direction: :ltr,
         vulnerable_player_id: nil,
         chain: nil,
         selected_cards: [],
         current_card_animation: nil
       )
       |> Phoenix.LiveView.put_private(:card_animation_queue, :queue.new())
       |> Phoenix.LiveView.put_private(:card_animation_seq, 0)}

  def handle_event("toggle-card", params, socket) do
    case SelectedCard.parse(params) do
      {:ok, selected} ->
        card = Card.format(:hand, selected.card)
        indexed_card = {card, selected.index}

        {:noreply,
         update(socket, :selected_cards, fn cards -> toggle_selected_card(cards, indexed_card) end)}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event(
        "dismiss_card_animation",
        %{"id" => id},
        %{
          assigns: %{current_card_animation: current},
          private: %{card_animation_queue: queue}
        } = socket
      )
      when not is_nil(current) and current.id == id do
    case :queue.out(queue) do
      {:empty, _} ->
        {:noreply, assign(socket, :current_card_animation, nil)}

      {{:value, next}, rest} ->
        {:noreply,
         socket
         |> Phoenix.LiveView.put_private(:card_animation_queue, rest)
         |> show_next_card_animation(next)}
    end
  end

  def handle_event("dismiss_card_animation", _params, socket), do: {:noreply, socket}

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

  def update(%{event: %Uno.Events.CardsPlayed{} = event}, socket) do
    {:ok,
     enqueue_card_animation(socket, %{
       kind: :played,
       actor_id: event.player_id,
       cards: event.played_cards
     })}
  end

  def update(%{event: %Uno.Events.CardsDrawn{} = event}, socket) do
    cards =
      if event.player_id == socket.assigns.player_id do
        event.drawn_cards
      else
        List.duplicate(:hidden, length(event.drawn_cards))
      end

    {:ok,
     enqueue_card_animation(socket, %{kind: :drawn, actor_id: event.player_id, cards: cards})}
  end

  def update(%{event: %Uno.Events.Sync{} = event}, %{assigns: %{player_id: player_id}} = socket) do
    hand = Map.fetch!(event.hands, player_id)

    players_before = Enum.take_while(event.players, fn {id, _} -> id != player_id end)

    players_after =
      Enum.drop_while(event.players, fn {id, _} -> id != player_id end) |> Enum.drop(1)

    {:ok,
     socket
     |> assign(
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
       chain: event.chain,
       current_card_animation: nil
     )
     |> Phoenix.LiveView.put_private(:card_animation_queue, :queue.new())}
  end

  def update(%{player_id: player_id}, socket) do
    {:ok, assign(socket, :player_id, player_id)}
  end

  # --- Private helpers

  defp enqueue_card_animation(
         %{
           assigns: %{current_card_animation: current},
           private: %{card_animation_queue: queue}
         } = socket,
         card_animation
       )
       when not is_nil(current),
       do:
         Phoenix.LiveView.put_private(
           socket,
           :card_animation_queue,
           :queue.in(card_animation, queue)
         )

  defp enqueue_card_animation(socket, card_animation),
    do: show_next_card_animation(socket, card_animation)

  defp show_next_card_animation(%{private: %{card_animation_seq: seq}} = socket, card_animation) do
    next_seq = seq + 1

    socket
    |> Phoenix.LiveView.put_private(:card_animation_seq, next_seq)
    |> assign(:current_card_animation, Map.put(card_animation, :id, next_seq))
  end

  # --- Private UI helpers ---

  defp toggle_selected_card(cards, selected)
  defp toggle_selected_card([], selected), do: [selected]
  defp toggle_selected_card([selected | rest], selected), do: rest

  defp toggle_selected_card([card | rest], selected),
    do: [card | toggle_selected_card(rest, selected)]

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

  defp card_animation_style(%{kind: :played, actor_id: actor}, player_id) when actor == player_id,
    do: "--card-start: 100%"

  defp card_animation_style(%{kind: :drawn, actor_id: actor}, player_id) when actor == player_id,
    do: "--card-end: 100%"

  defp card_animation_style(%{kind: :played}, _player_id),
    do: "--card-start: -100%"

  defp card_animation_style(%{kind: :drawn}, _player_id),
    do: "--card-end: -100%"
end
