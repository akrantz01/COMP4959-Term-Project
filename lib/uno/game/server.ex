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

  # GS-3: Validates the play, applies cards to the logic state, and broadcasts
  # the resulting events. Handles chain accumulation and winner detection.
  @impl true
  def handle_call({:play, player_id, cards}, _from, state) do
    with :ok <- validate_multi_play(cards),
         {:ok, new_chain} <- Logic.apply_chain(state.chain, cards),
         {:ok, new_logic} <- apply_cards(state.logic_state, player_id, cards) do
      player_hand = new_logic |> Logic.player_hands() |> Map.get(player_id, [])

      # TODO GS-4: iterate skip_count times, calling Logic.skip/2 and broadcasting
      # next_turn for each skipped player (requires pb_task_15 to merge)
      _skip_count = Logic.apply_skip(cards)

      new_state = %{state | logic_state: new_logic, chain: new_chain}

      broadcast_cards_played(new_state, player_id, cards, player_hand)

      if Enum.empty?(player_hand) do
        # Player has emptied their hand — game over
        Uno.PubSub.broadcast({:game, state.room_id}, %Events.GameEnded{winner_id: player_id})
        {:stop, :normal, :ok, new_state}
      else
        broadcast_next_turn(new_state, false)
        {:reply, :ok, new_state}
      end
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
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

  # -------------------- Private Helpers --------------------

  # Returns :ok if cards form a legal multi-play group, error otherwise
  @spec validate_multi_play([Logic.played_card()]) :: :ok | {:error, :invalid_multi_play}
  defp validate_multi_play(cards) do
    if Logic.valid_multi_play?(cards), do: :ok, else: {:error, :invalid_multi_play}
  end

  # Applies each card to the logic state in sequence.
  # NOTE: Logic.play_cards/3 advances the turn per card, so multi-card plays (>1 card)
  # will fail on the second card until Logic exposes a list-based play API.
  @spec apply_cards(Logic.t(), Logic.player_id(), [Logic.played_card()]) ::
          {:ok, Logic.t()} | {:error, atom()}
  defp apply_cards(logic, player_id, cards) do
    Enum.reduce_while(cards, {:ok, logic}, fn card, {:ok, current_logic} ->
      case Logic.play_cards(current_logic, player_id, card) do
        {:ok, new_logic} -> {:cont, {:ok, new_logic}}
        error -> {:halt, error}
      end
    end)
  end

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
