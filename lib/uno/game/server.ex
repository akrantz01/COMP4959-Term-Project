defmodule Uno.Game.Server do
  use GenServer

  @moduledoc """
  Exposes an `Uno.Game.Logic` instance for clients to use.

  Handles all client interactions and timing-related behaviours.
  """

  alias Uno.Game.Logic
  alias Phoenix.PubSub

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
  def init({room_id, player_ids}) do
    PubSub.subscribe(Uno.PubSub, "game:#{room_id}")

    initial_logic_state = Logic.new(player_ids)

    server_state = %{
      room_id: room_id,
      logic_state: initial_logic_state,
      auto_play_set: MapSet.new(),
      timers: %{}
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

  @impl true
  def handle_call({:play, _player_id, _cards}, _from, state) do
    {:reply, :ok, state}
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
end
