defmodule UnoWeb.RoomLive.GameComponent do
  use UnoWeb, :live_component

  alias Phoenix.LiveView.JS
  alias UnoWeb.Forms.{Card, SelectedCard}

  attr :player_id, :string, required: true

  def mount(socket),
    do:
      {:ok,
       socket
       |> assign(
         room_id: nil,
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
         uno_called: false,
         current_card_animation: nil
       )
       |> Phoenix.LiveView.put_private(:card_animation_queue, :queue.new())
       |> Phoenix.LiveView.put_private(:card_animation_seq, 0)}

  def handle_event("toggle-card", params, %{assigns: %{selected_cards: selected_cards}} = socket) do
    with {:ok, selected} <- SelectedCard.parse(params),
         card = Card.format(:played, selected.card),
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

  def handle_event(
        "play",
        _unsigned_params,
        %{
          assigns: %{
            player_id: player_id,
            turn_player_id: player_id,
            selected_cards: []
          }
        } = socket
      ),
      do: {:noreply, put_flash(socket, :error, "No cards selected!")}

  def handle_event(
        "play",
        _unsigned_params,
        %{
          assigns: %{
            player_id: player_id,
            turn_player_id: player_id,
            selected_cards: selected_cards
          }
        } = socket
      ) do
    _selected_cards = Enum.map(selected_cards, fn {card, _} -> card end)
    # TODO: call game to play card(s)
    {:noreply, assign(socket, :selected_cards, [])}
  end

  def handle_event("play", _unsigned_params, socket),
    do: {:noreply, put_flash(socket, :error, "It's not your turn!")}

  def handle_event(
        "draw",
        _unsigned_params,
        %{
          assigns: %{
            player_id: player_id,
            turn_player_id: player_id,
            hand: hand,
            top_card: top_card
          }
        } = socket
      ) do
    if hand_size(hand) > 20 && !has_playable_card?(hand, top_card) do
      # TODO: call game to draw card(s)
      {:noreply, socket}
    else
      {:noreply, put_flash(socket, :error, "You have too many cards!")}
    end
  end

  def handle_event("draw", _unsigned_params, socket),
    do: {:noreply, put_flash(socket, :error, "It's not your turn!")}

  def handle_event(
        "accept-chain",
        _unsigned_params,
        %{assigns: %{player_id: player_id, turn_player_id: player_id, chain: nil}} = socket
      ),
      do: {:noreply, put_flash(socket, :error, "No chain is active")}

  def handle_event(
        "accept-chain",
        _unsigned_params,
        %{assigns: %{player_id: player_id, turn_player_id: player_id}} = socket
      ) do
    # TODO: call game to accept chain
    {:noreply, socket}
  end

  def handle_event("accept-chain", _unsigned_params, socket),
    do: {:noreply, put_flash(socket, :error, "It's not your turn!")}

  def handle_event("uno", _unsigned_params, %{assigns: %{uno_called: false}} = socket) do
    # TODO: call game to call UNO!
    {:noreply, assign(socket, :uno_called, true)}
  end

  def handle_event("uno", _unsigned_params, %{assigns: %{uno_called: true}} = socket),
    do: {:noreply, put_flash(socket, :error, "Already called UNO! this turn!")}

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
    if event.sequence <= socket.assigns.sequence do
      {:ok, socket}
    else
      {:ok,
       assign(socket,
         sequence: event.sequence,
         turn_player_id: event.player_id,
         turn_skipped: event.skipped,
         top_card: event.top_card,
         direction: event.direction,
         vulnerable_player_id: event.vulnerable_player_id,
         chain: event.chain,
         uno_called: false
       )}
    end
  end

  def update(%{event: %Uno.Events.CardsPlayed{} = event}, socket) do
    {:ok,
     socket
     |> update_hands(event)
     |> enqueue_card_animation(%{
       kind: :played,
       actor_id: event.player_id,
       cards: event.played_cards
     })}
  end

  def update(
        %{event: %Uno.Events.CardsDrawn{} = event},
        %{assigns: %{player_id: player_id}} = socket
      ) do
    cards =
      if event.player_id == player_id do
        event.drawn_cards
      else
        List.duplicate(:hidden, length(event.drawn_cards))
      end

    {:ok,
     socket
     |> update_hands(event)
     |> enqueue_card_animation(%{kind: :drawn, actor_id: event.player_id, cards: cards})}
  end

  def update(%{event: %Uno.Events.Sync{} = event}, socket) do
    {:ok, apply_sync(socket, event)}
  end

  # Assign directly passed in properties. On first delivery (room_id was nil),
  # pull the authoritative game state — clients don't receive an initial Sync
  # broadcast, so they populate themselves synchronously from the Game server.
  def update(%{id: _id, room_id: room_id, player_id: player_id}, socket) do
    first_delivery? = is_nil(socket.assigns.room_id)
    socket = assign(socket, room_id: room_id, player_id: player_id)

    if first_delivery? do
      {:ok, apply_sync(socket, Uno.Game.Server.snapshot(room_id))}
    else
      {:ok, socket}
    end
  end

  # --- Private helpers

  defp apply_sync(%{assigns: %{player_id: player_id}} = socket, %Uno.Events.Sync{} = event) do
    hand = Map.fetch!(event.hands, player_id)

    players_before = Enum.take_while(event.players, fn {id, _} -> id != player_id end)

    players_after =
      Enum.drop_while(event.players, fn {id, _} -> id != player_id end) |> Enum.drop(1)

    socket
    |> assign(
      sequence: event.sequence,
      hand: hand,
      opponents:
        Enum.map(players_after ++ players_before, fn {id, name} ->
          %{
            id: id,
            name: name,
            cards: Map.get(event.hands, id, %{}) |> hand_size()
          }
        end),
      top_card: event.top_card,
      turn_player_id: event.current_player_id,
      direction: event.direction,
      vulnerable_player_id: event.vulnerable_player_id,
      chain: event.chain,
      current_card_animation: nil
    )
    |> Phoenix.LiveView.put_private(:card_animation_queue, :queue.new())
  end

  defp has_playable_card?(hand, top_card) do
    {top_colour, top_type} = card_parts(top_card)

    Map.keys(hand)
    |> Enum.any?(fn card ->
      case card do
        wild when wild in ~w(wild wild_draw_4)a -> true
        {^top_colour, _type} -> true
        {_colour, ^top_type} -> true
        _ -> false
      end
    end)
  end

  defp update_hands(
         %{assigns: %{player_id: player_id}} = socket,
         %{player_id: actor_id, hand: hand}
       )
       when player_id == actor_id,
       do: assign(socket, :hand, hand)

  defp update_hands(
         %{assigns: %{opponents: opponents}} = socket,
         %{player_id: player_id, hand: hand}
       ) do
    index = Enum.find_index(opponents, fn %{id: id} -> player_id == id end)

    if is_integer(index) do
      assign(
        socket,
        :opponents,
        List.update_at(opponents, index, fn item ->
          Map.put(item, :cards, hand_size(hand))
        end)
      )
    else
      socket
    end
  end

  defp hand_size(hand), do: Map.values(hand) |> Enum.sum()

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

  attr :direction, :atom, values: ~w(ltr rtl)a

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

  attr :show, :boolean, required: true

  defp skip_icon_overlay(assigns) do
    ~H"""
    <div
      class={[
        "absolute inset-0 flex items-center justify-center bg-black/60 transition-opacity duration-300",
        if(@show, do: "opacity-100", else: "opacity-0 pointer-events-none")
      ]}
      aria-hidden={not @show}
    >
      <.icon name="fas-ban" class="size-10 text-red-500" />
    </div>
    """
  end

  defp flatten_hand(hand),
    do:
      Enum.filter(hand, fn {_, count} -> count > 0 end)
      |> Enum.sort_by(fn {card, _} -> card_order(card) end)

  defp card_parts(:wild), do: {nil, :wild}
  defp card_parts(:wild_draw_4), do: {nil, :wild_draw_4}
  defp card_parts({wild, _colour}) when wild in [:wild, :wild_draw_4], do: {nil, wild}
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

  defp card_selected?(selected_cards, card, i) when card in [:wild, :wild_draw_4] do
    Enum.any?(selected_cards, fn
      {{^card, _colour}, ^i} -> true
      _ -> false
    end)
  end

  defp card_selected?(selected_cards, card, i),
    do: Enum.member?(selected_cards, {card, i})

  defp selected_wild_colour(selected_cards, card, i) do
    Enum.find_value(selected_cards, fn
      {{^card, colour}, ^i} -> colour
      _ -> nil
    end)
  end

  defp card_animation_style(%{kind: :played, actor_id: actor}, player_id) when actor == player_id,
    do: "--card-start: 100%"

  defp card_animation_style(%{kind: :drawn, actor_id: actor}, player_id) when actor == player_id,
    do: "--card-end: 100%"

  defp card_animation_style(%{kind: :played}, _player_id),
    do: "--card-start: -100%"

  defp card_animation_style(%{kind: :drawn}, _player_id),
    do: "--card-end: -100%"
end
