defmodule Uno.Game.Server do
  use GenServer

  @moduledoc """
  Exposes an `Uno.Game.Logic` instance for clients to use.

  Handles all client interactions and timing-related behaviours.
  """

  alias Uno.Events
  alias Uno.Game.Logic

  @broadcast_delay 200
  @disconnect_timeout 60_000
  @inactivity_timeout 30_000
  @uno_grace_period 500

  @doc """
  Starts the GenServer with the given room ID and player list.
  """
  def start_link(room_id, player_ids) do
    GenServer.start_link(__MODULE__, {room_id, player_ids}, name: via_tuple(room_id))
  end

  defp via_tuple(room_id) do
    {:via, Registry, {Uno.Game.Registry, room_id}}
  end

  # -------------------- APIs --------------------

  @doc """
  Interface for player connecting to the game.
  """
  def connect(server, player_id) do
    GenServer.cast(via_tuple(server), {:connect, player_id})
  end

  @doc """
  Interface for disconnecting from the game.
  """
  def disconnect(server, player_id) do
    GenServer.cast(via_tuple(server), {:disconnect, player_id})
  end

  @doc """
  Interface for playing cards.
  """
  def play(server, player_id, cards) do
    GenServer.call(via_tuple(server), {:play, player_id, cards})
  end

  @doc """
  Interface for drawing a card.
  """
  def draw(server, player_id) do
    GenServer.call(via_tuple(server), {:draw, player_id})
  end

  @doc """
  Interface for accepting a draw chain.
  """
  def accept_chain(server, player_id) do
    GenServer.call(via_tuple(server), {:accept_chain, player_id})
  end

  @doc """
  Interface for calling UNO.
  """
  def uno(server, player_id) do
    GenServer.call(via_tuple(server), {:uno, player_id})
  end

  @doc """
  Returns the full game state as an `Events.Sync` struct.
  """
  def snapshot(room_id) do
    GenServer.call(via_tuple(room_id), :snapshot)
  end

  # -------------------- Event Handlers --------------------

  # GS-14: Fires when a player's 30s inactivity timer expires.
  # Sequence number guards against stale timers — if the turn has advanced, this is a no-op.
  # Only acts if the player is still the current player and the sequence matches.
  defp inactivity_timeout(state, player_id, sequence_number) do
    logic = state.logic_state

    if logic != nil and
         logic.sequence == sequence_number and
         Logic.current_turn(logic) == player_id do
      handle_auto_play(state, player_id)
    else
      state
    end
  end

  # GS-15: Plays the first valid card for the player, or draws until one is found.
  # Guard: no-op if it is not this player's turn (stale auto_play timer or inactivity fire).
  defp handle_auto_play(state, player_id) do
    logic = state.logic_state

    if logic == nil or Logic.current_turn(logic) != player_id do
      state
    else
      case Logic.next_playable_card(logic, player_id) do
        nil -> draw_until_playable(state, player_id)
        card -> auto_play_card(state, player_id, [to_played_card(card)])
      end
    end
  end

  # -------------------- Server Callbacks --------------------

  @impl true
  def init({room_id, player_ids}) do
    initial_logic_state = Logic.init(player_ids)

    server_state = %{
      room_id: room_id,
      logic_state: initial_logic_state,
      auto_play_set: MapSet.new(),
      chain: nil,
      broadcast_queue: :queue.new(),
      broadcast_pending: false,
      vulnerable_players: %{}
    }

    {:ok, server_state}
  end

  # GS-12: Remove from auto-play set and broadcast full game state to all subscribers.
  @impl true
  def handle_cast({:connect, player_id}, state) do
    new_state = %{state | auto_play_set: MapSet.delete(state.auto_play_set, player_id)}

    new_state =
      if new_state.logic_state != nil do
        enqueue_broadcast(new_state, build_sync(new_state))
      else
        new_state
      end

    {:noreply, new_state}
  end

  # GS-13: Add to auto-play set and schedule auto-turn after 60s.
  # The auto_play_set acts as the stale-timer guard: if the player reconnects
  # before the timer fires, GS-12 removes them from the set and handle_auto_play is a no-op.
  # Sequence number prevents stale fires if the player reconnects and disconnects again.
  @impl true
  def handle_cast({:disconnect, player_id}, state) do
    new_state = %{state | auto_play_set: MapSet.put(state.auto_play_set, player_id)}
    sequence = if new_state.logic_state != nil, do: new_state.logic_state.sequence, else: -1
    Process.send_after(self(), {:auto_play, player_id, sequence}, @disconnect_timeout)
    {:noreply, new_state}
  end

  # GS-3/GS-4: Applies the full card list via Logic, broadcasts results.
  # Logic.play_cards/3 now handles validation, chain, and skip advancement internally.
  @impl true
  def handle_call({:play, player_id, cards}, _from, state) do
    old_logic = state.logic_state

    case Logic.play_cards(old_logic, player_id, cards) do
      {:ok, new_logic} ->
        player_hand = new_logic |> Logic.player_hands() |> Map.get(player_id, [])
        new_state = %{state | logic_state: new_logic, chain: new_logic.chain}
        new_state = mark_vulnerability(new_state, player_id, player_hand)

        new_state = broadcast_cards_played(new_state, player_id, cards, player_hand)
        new_state = resolve_pending_penalties(new_state)

        case maybe_emit_game_ended(new_state, player_id, player_hand) do
          {:game_ended, ended_state} ->
            {:stop, :normal, :ok, ended_state}

          {:continue, continuing_state} ->
            skip_count = count_skips(cards)
            continuing_state = apply_skips(old_logic, continuing_state, skip_count)
            continuing_state = broadcast_next_turn(continuing_state, false)
            continuing_state = start_inactivity_timer(continuing_state)
            {:reply, :ok, continuing_state}
        end

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:draw, player_id}, _from, state) do
    result =
      if Logic.next_playable_card(state.logic_state, player_id) != nil do
        case Logic.draw_card(state.logic_state, player_id) do
          {:ok, updated_logic, drawn_card, _status} -> {:ok, updated_logic, [drawn_card]}
          {:error, reason} -> {:error, reason}
        end
      else
        draw_loop(state.logic_state, player_id, [])
      end

    case result do
      {:ok, updated_logic, drawn_cards} ->
        new_hand = updated_logic |> Logic.player_hands() |> Map.get(player_id, [])
        new_state = %{state | logic_state: updated_logic}
        new_state = broadcast_cards_drawn(new_state, player_id, drawn_cards, new_hand)
        {:reply, {:ok, drawn_cards}, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:accept_chain, player_id}, _from, state) do
    case Logic.accept_chain(state.logic_state, player_id) do
      {:ok, updated_logic} ->
        # Increment sequence to ensure frontend accepts the NextTurn event
        updated_logic = %{updated_logic | sequence: updated_logic.sequence + 1}
        new_state = %{state | logic_state: updated_logic, chain: updated_logic.chain}
        new_state = resolve_pending_penalties(new_state)
        new_state = broadcast_next_turn(new_state, false)
        new_state = start_inactivity_timer(new_state)

        {:reply, :ok, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(:snapshot, _from, state) do
    {:reply, build_sync(state), state}
  end

  @impl true
  def handle_call({:uno, player_id}, _from, state) do
    case state.logic_state do
      nil ->
        {:reply, {:error, :game_not_started}, state}

      logic ->
        handle_uno_call(state, player_id, logic)
    end
  end

  @impl true
  def handle_info({:inactivity_timeout, player_id, sequence_number}, state) do
    {:noreply, inactivity_timeout(state, player_id, sequence_number)}
  end

  @impl true
  def handle_info({:auto_play, player_id, sequence_number}, state) do
    if MapSet.member?(state.auto_play_set, player_id) and
         state.logic_state != nil and
         state.logic_state.sequence == sequence_number do
      {:noreply, handle_auto_play(state, player_id)}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info({:uno_call_buffer, player_id, sequence_number}, state) do
    case state.logic_state do
      nil ->
        {:noreply, state}

      logic ->
        handle_uno_call_buffer(state, player_id, logic, sequence_number)
    end
  end

  # GS-11: Drains one event from the broadcast queue; reschedules if more remain.
  @impl true
  def handle_info(:flush_broadcast_queue, state) do
    case :queue.out(state.broadcast_queue) do
      {{:value, event}, remaining} ->
        Uno.PubSub.broadcast({:game, state.room_id}, event)
        Process.send_after(self(), :flush_broadcast_queue, @broadcast_delay)
        {:noreply, %{state | broadcast_queue: remaining}}

      {:empty, _} ->
        {:noreply, %{state | broadcast_pending: false}}
    end
  end

  # -------------------- Private Helpers --------------------

  defp handle_uno_call_buffer(state, player_id, logic, sequence_number) do
    vulnerable_player = logic.vulnerable_player_id

    if logic.sequence == sequence_number and vulnerable_player != nil do
      case process_uno_call(state, player_id) do
        {:reply, _response, new_state} -> {:noreply, new_state}
      end
    else
      {:noreply, state}
    end
  end

  defp handle_uno_call(state, player_id, logic) do
    vulnerable_player_id = logic.vulnerable_player_id

    if vulnerable_player_id != nil and vulnerable_player_id != player_id do
      handle_uno_with_vulnerable(state, player_id, logic, vulnerable_player_id)
    else
      process_uno_call(state, player_id)
    end
  end

  defp handle_uno_with_vulnerable(state, player_id, logic, vulnerable_player_id) do
    case Map.get(state.vulnerable_players, vulnerable_player_id) do
      vulnerable_timestamp when is_integer(vulnerable_timestamp) ->
        current_time = System.monotonic_time(:millisecond)
        delay = vulnerable_timestamp + @uno_grace_period - current_time

        if delay > 0 do
          Process.send_after(self(), {:uno_call_buffer, player_id, logic.sequence}, delay)
          {:reply, :ok, state}
        else
          process_uno_call(state, player_id)
        end

      _ ->
        process_uno_call(state, player_id)
    end
  end

  defp process_uno_call(state, player_id) do
    case Logic.uno(state.logic_state, player_id) do
      {:ok, updated_logic, _penalties_map} ->
        new_state =
          state
          |> Map.put(:logic_state, updated_logic)
          |> sync_vulnerability(updated_logic)
          |> resolve_pending_penalties()

        {:reply, :ok, new_state}
    end
  end

  # GS-14: Schedules an inactivity timeout for the current player if they are not in auto_play_set.
  # The sequence number is embedded so stale timer fires are no-ops in inactivity_timeout/3.
  @spec start_inactivity_timer(map()) :: map()
  defp start_inactivity_timer(state) do
    logic = state.logic_state
    player_id = Logic.current_turn(logic)

    if MapSet.member?(state.auto_play_set, player_id) do
      Process.send_after(self(), {:auto_play, player_id, logic.sequence}, 0)
    else
      Process.send_after(
        self(),
        {:inactivity_timeout, player_id, logic.sequence},
        @inactivity_timeout
      )
    end

    state
  end

  defp mark_vulnerability(state, player_id, player_hand) do
    vulnerable_players =
      if Enum.count(player_hand) == 1 do
        %{player_id => System.monotonic_time(:millisecond)}
      else
        %{}
      end

    %{state | vulnerable_players: vulnerable_players}
  end

  defp sync_vulnerability(state, updated_logic) do
    vulnerable_players =
      case updated_logic.vulnerable_player_id do
        nil -> %{}
        player_id -> Map.take(state.vulnerable_players, [player_id])
      end

    %{state | vulnerable_players: vulnerable_players}
  end

  defp resolve_pending_penalties(state) do
    state.logic_state.penalties
    |> Enum.filter(fn {_player_id, count} -> count > 0 end)
    |> Enum.reduce(state, fn {player_id, _count}, acc ->
      draw_penalty_cards(acc, player_id)
    end)
  end

  defp draw_penalty_cards(state, player_id) do
    case Logic.draw_card(state.logic_state, player_id) do
      {:ok, new_logic, drawn_card, status}
      when status in [:penalty_continue, :penalty_complete] ->
        new_hand = new_logic |> Logic.player_hands() |> Map.get(player_id, [])
        new_state = %{state | logic_state: new_logic}
        new_state = broadcast_cards_drawn(new_state, player_id, [drawn_card], new_hand)

        if status == :penalty_continue do
          draw_penalty_cards(new_state, player_id)
        else
          new_state
        end
    end
  end

  # GS-15: Draws one card at a time until the drawn card is playable, then plays it.
  @spec draw_until_playable(map(), Logic.player_id()) :: map()
  defp draw_until_playable(state, player_id) do
    {:ok, new_logic, drawn_card, status} = Logic.draw_card(state.logic_state, player_id)
    new_hand = new_logic |> Logic.player_hands() |> Map.get(player_id, [])
    new_state = %{state | logic_state: new_logic}
    new_state = broadcast_cards_drawn(new_state, player_id, [drawn_card], new_hand)

    if status == :playable do
      card = Logic.next_playable_card(new_logic, player_id) |> to_played_card()
      auto_play_card(new_state, player_id, [card])
    else
      draw_until_playable(new_state, player_id)
    end
  end

  # GS-15: Executes a play on behalf of the auto-play player and broadcasts results.
  @spec auto_play_card(map(), Logic.player_id(), [Logic.played_card()]) :: map()
  defp auto_play_card(state, player_id, cards) do
    old_logic = state.logic_state

    case Logic.play_cards(old_logic, player_id, cards) do
      {:ok, new_logic} ->
        player_hand = new_logic |> Logic.player_hands() |> Map.get(player_id, [])
        new_state = %{state | logic_state: new_logic, chain: new_logic.chain}
        new_state = mark_vulnerability(new_state, player_id, player_hand)

        new_state = broadcast_cards_played(new_state, player_id, cards, player_hand)
        new_state = resolve_pending_penalties(new_state)

        case maybe_emit_game_ended(new_state, player_id, player_hand) do
          {:game_ended, ended_state} ->
            ended_state

          {:continue, continuing_state} ->
            skip_count = count_skips(cards)
            continuing_state = apply_skips(old_logic, continuing_state, skip_count)
            continuing_state = broadcast_next_turn(continuing_state, false)
            start_inactivity_timer(continuing_state)
        end

      {:error, _reason} ->
        state
    end
  end

  # Enqueues the cards_drawn event with the player's updated hand as a frequency map.
  @spec broadcast_cards_drawn(map(), Logic.player_id(), [Logic.hand_card()], [
          Logic.hand_card()
        ]) :: map()
  defp broadcast_cards_drawn(state, player_id, drawn_cards, hand) do
    enqueue_broadcast(state, %Events.CardsDrawn{
      player_id: player_id,
      drawn_cards: drawn_cards,
      hand: Enum.frequencies(hand)
    })
  end

  # Converts a hand_card to a played_card, picking :red for wilds.
  @spec to_played_card(Logic.hand_card()) :: Logic.played_card()
  defp to_played_card(:wild), do: {:wild, :red}
  defp to_played_card(:wild_draw_4), do: {:wild_draw_4, :red}
  defp to_played_card(card), do: card

  defp maybe_emit_game_ended(state, player_id, player_hand) do
    if Enum.empty?(player_hand) do
      {:game_ended, enqueue_broadcast(state, %Events.GameEnded{winner_id: player_id})}
    else
      {:continue, state}
    end
  end

  # Builds a full-state Sync event from the current logic state.
  @spec build_sync(map()) :: Events.Sync.t()
  defp build_sync(state) do
    logic = state.logic_state

    players_map = logic.players |> :queue.to_list() |> Map.new(fn {id, name} -> {id, name} end)

    hands_map =
      logic
      |> Logic.player_hands()
      |> Map.new(fn {id, hand} -> {id, Enum.frequencies(hand)} end)

    %Events.Sync{
      sequence: logic.sequence,
      current_player_id: Logic.current_turn(logic),
      top_card: logic.top_card,
      direction: logic.direction,
      hands: hands_map,
      players: players_map,
      vulnerable_player_id: logic.vulnerable_player_id,
      chain: state.chain
    }
  end

  # GS-11: Sends event immediately if no broadcast is in flight; otherwise enqueues it.
  # The first event in a burst goes out at t=0; each subsequent one waits @broadcast_delay ms.
  @spec enqueue_broadcast(map(), struct()) :: map()
  defp enqueue_broadcast(state, event) do
    if state.broadcast_pending do
      %{state | broadcast_queue: :queue.in(event, state.broadcast_queue)}
    else
      Uno.PubSub.broadcast({:game, state.room_id}, event)
      Process.send_after(self(), :flush_broadcast_queue, @broadcast_delay)
      %{state | broadcast_pending: true}
    end
  end

  # Enqueues the cards_played event with the player's updated hand as a frequency map.
  @spec broadcast_cards_played(map(), Logic.player_id(), [Logic.played_card()], [
          Logic.hand_card()
        ]) :: map()
  defp broadcast_cards_played(state, player_id, cards, hand) do
    enqueue_broadcast(state, %Events.CardsPlayed{
      player_id: player_id,
      played_cards: cards,
      hand: Enum.frequencies(hand)
    })
  end

  # Counts how many skip cards are in the played list.
  @spec count_skips([Logic.played_card()]) :: non_neg_integer()
  defp count_skips(cards) do
    Enum.count(cards, fn
      {_colour, :skip} -> true
      _ -> false
    end)
  end

  # Enqueues NextTurn(skipped: true) for each skipped player.
  # play_cards already advanced the turn past all of them, so we derive their IDs
  # by peeking at the old state's player queue (positions 1..skip_count after current).
  @spec apply_skips(Logic.t(), map(), non_neg_integer()) :: map()
  defp apply_skips(_old_logic, state, 0), do: state

  defp apply_skips(old_logic, state, skip_count) do
    old_logic.players
    |> :queue.to_list()
    |> Enum.drop(1)
    |> Enum.take(skip_count)
    |> Enum.reduce(state, fn {skipped_id, _name}, acc ->
      enqueue_broadcast(acc, %Events.NextTurn{
        sequence: acc.logic_state.sequence,
        player_id: skipped_id,
        top_card: acc.logic_state.top_card,
        direction: acc.logic_state.direction,
        vulnerable_player_id: acc.logic_state.vulnerable_player_id,
        skipped: true,
        chain: acc.chain
      })
    end)
  end

  # Enqueues the next_turn event for the current logic state's active player.
  @spec broadcast_next_turn(map(), boolean()) :: map()
  defp broadcast_next_turn(state, skipped) do
    logic = state.logic_state

    enqueue_broadcast(state, %Events.NextTurn{
      sequence: logic.sequence,
      player_id: Logic.current_turn(logic),
      top_card: logic.top_card,
      direction: logic.direction,
      vulnerable_player_id: logic.vulnerable_player_id,
      skipped: skipped,
      chain: state.chain
    })
  end

  defp draw_loop(logic_state, player_id, cards_drawn) do
    case Logic.draw_card(logic_state, player_id) do
      {:ok, updated_logic, drawn_card, :playable} ->
        {:ok, updated_logic, cards_drawn ++ [drawn_card]}

      {:ok, updated_logic, drawn_card, :unplayable} ->
        draw_loop(updated_logic, player_id, cards_drawn ++ [drawn_card])

      {:error, reason} ->
        {:error, reason}
    end
  end
end
