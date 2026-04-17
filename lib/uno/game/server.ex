defmodule Uno.Game.Server do
  use GenServer

  @moduledoc """
  Exposes an `Uno.Game.Logic` instance for clients to use.

  Handles all client interactions and timing-related behaviours.
  """

  alias Phoenix.PubSub
  alias Uno.Events
  alias Uno.Game.Logic

  @doc """
  Starts the GenServer with the given room ID and player list.
  """
  def start_link(room_id, player_ids) do
    GenServer.start_link(__MODULE__, {room_id, player_ids})
  end

  # -------------------- APIs --------------------

  @doc """
  Interface for player connecting to the game.
  """
  def connect(server, player_id) do
    GenServer.cast(server, {:connect, player_id})
  end

  @doc """
  Interface for disconnecting from the game.
  """
  def disconnect(server, player_id) do
    GenServer.cast(server, {:disconnect, player_id})
  end

  @doc """
  Interface for playing cards.
  """
  def play(server, player_id, cards) do
    GenServer.call(server, {:play, player_id, cards})
  end

  @doc """
  Interface for drawing a card.
  """
  def draw(server, player_id) do
    GenServer.call(server, {:draw, player_id})
  end

  @doc """
  Interface for accepting a draw chain.
  """
  def accept_chain(server, player_id) do
    GenServer.call(server, {:accept_chain, player_id})
  end

  @doc """
  Interface for calling UNO.
  """
  def uno(server, player_id) do
    GenServer.call(server, {:uno, player_id})
  end

  # -------------------- Event Handlers --------------------

  # Handles the inactivity timer expiring for a player's turn
  defp inactivity_timeout(state, _player_id, _sequence_number), do: state

  # Handles auto-play for a disconnected player
  defp handle_auto_play(state, _player_id), do: state

  # UNO call grace period expiring
  defp expire_uno_call_buffer(state, _player_id, _sequence_number), do: state

  # -------------------- Server Callbacks --------------------

  @impl true
  def init({room_id, _player_ids}) do
    PubSub.subscribe(Uno.PubSub, "game:#{room_id}")

    # initial_logic_state = Logic.new(player_ids)
    initial_logic_state = nil

    server_state = %{
      room_id: room_id,
      logic_state: initial_logic_state,
      auto_play_set: MapSet.new(),
      timers: %{},
      chain: nil
    }

    {:ok, server_state}
  end

  @impl true
  def handle_cast({:connect, _player_id}, state) do
    {:noreply, state}
  end

  @impl true
  def handle_cast({:disconnect, _player_id}, state) do
    {:noreply, state}
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

        broadcast_cards_played(new_state, player_id, cards, player_hand)

        if Enum.empty?(player_hand) do
          Uno.PubSub.broadcast({:game, state.room_id}, %Events.GameEnded{winner_id: player_id})
          {:stop, :normal, :ok, new_state}
        else
          skip_count = count_skips(cards)
          apply_skips(old_logic, new_state, skip_count)
          broadcast_next_turn(new_state, false)
          {:reply, :ok, new_state}
        end

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:draw, _player_id}, _from, state) do
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:accept_chain, _player_id}, _from, state) do
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:uno, _player_id}, _from, state) do
    {:reply, :ok, state}
  end

  @impl true
  def handle_info({:inactivity_timeout, player_id, sequence_number}, state) do
    {:noreply, inactivity_timeout(state, player_id, sequence_number)}
  end

  @impl true
  def handle_info({:auto_play, player_id}, state) do
    {:noreply, handle_auto_play(state, player_id)}
  end

  @impl true
  def handle_info({:uno_call_buffer, player_id, sequence_number}, state) do
    {:noreply, expire_uno_call_buffer(state, player_id, sequence_number)}
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  # -------------------- Private Helpers --------------------

  # Broadcasts the cards_played event with the player's updated hand as a frequency map
  @spec broadcast_cards_played(map(), Logic.player_id(), [Logic.played_card()], [
          Logic.hand_card()
        ]) :: :ok | {:error, term()}
  defp broadcast_cards_played(state, player_id, cards, hand) do
    Uno.PubSub.broadcast({:game, state.room_id}, %Events.CardsPlayed{
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

  # Broadcasts NextTurn(skipped: true) for each skipped player.
  # play_cards already advanced the turn past all of them, so we derive their IDs
  # by peeking at the old state's player queue (positions 1..skip_count after current).
  @spec apply_skips(Logic.t(), map(), non_neg_integer()) :: :ok
  defp apply_skips(_old_logic, _state, 0), do: :ok

  defp apply_skips(old_logic, state, skip_count) do
    old_logic.players
    |> :queue.to_list()
    |> Enum.drop(1)
    |> Enum.take(skip_count)
    |> Enum.each(fn {skipped_id, _name} ->
      Uno.PubSub.broadcast({:game, state.room_id}, %Events.NextTurn{
        sequence: state.logic_state.sequence,
        player_id: skipped_id,
        top_card: state.logic_state.top_card,
        direction: state.logic_state.direction,
        skipped: true,
        chain: state.chain
      })
    end)
  end

  # Broadcasts the next_turn event for the current logic state's active player
  @spec broadcast_next_turn(map(), boolean()) :: :ok | {:error, term()}
  defp broadcast_next_turn(state, skipped) do
    logic = state.logic_state

    Uno.PubSub.broadcast({:game, state.room_id}, %Events.NextTurn{
      sequence: logic.sequence,
      player_id: Logic.current_turn(logic),
      top_card: logic.top_card,
      direction: logic.direction,
      skipped: skipped,
      chain: state.chain
    })
  end
end
