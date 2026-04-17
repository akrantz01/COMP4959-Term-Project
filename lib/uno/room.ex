defmodule Uno.Room do
  @moduledoc """
  Exposes an 'Uno.Room' for clients to connect with.

  Handles room creation, player membership, game lifecycle, and room statistics.

  The room state includes:
  - `room_id`: Unique identifier for the room.
  - `state`: `:lobby` or `:in_game`.
  - `players`: Map of player IDs to player metadata.
  - `admin_id`: Player ID of the current room admin.
  - `last_winner_id`: Player ID of the last winning player.
  - `games_played`: Number of completed games in this room.
  """

  use GenServer

  alias Uno.Events, as: Events
  alias Uno.PubSub

  @type room_state :: :lobby | :in_game

  @type player_meta :: %{
          name: String.t(),
          connected: boolean(),
          wins: non_neg_integer()
        }

  @enforce_keys [:room_id]
  defstruct [
    :room_id,
    state: :lobby,
    players: %{},
    admin_id: nil,
    last_winner_id: nil,
    games_played: 0
  ]

  @typedoc """
  The type definition for the Uno.Room struct.
  """
  @type t :: %__MODULE__{
          room_id: Uno.Events.room_id(),
          state: room_state(),
          players: %{String.t() => player_meta()},
          admin_id: String.t() | nil,
          last_winner_id: String.t() | nil,
          games_played: non_neg_integer()
        }

  @typep state :: t()

  @type call_result ::
          :ok
          | {:ok, Events.PlayerJoined.t()}
          | {:error, :player_not_found | :room_not_in_lobby | :not_room_admin}

  @spec start_link(any()) :: :ignore | {:error, any()} | {:ok, pid()}
  @doc """
  Starts the Uno.Room GenServer with the given room_id.
  """
  def start_link(room_id) do
    GenServer.start_link(__MODULE__, room_id, name: via_tuple(room_id))
  end

  @spec via_tuple(String.t()) :: {:via, Registry, {Uno.Room.Registry, String.t()}}
  def via_tuple(room_id) do
    {:via, Registry, {Uno.Room.Registry, room_id}}
  end

  # Public API

  @doc """
  Join a player to the room.

  Returns
    `{:ok, %Events.PlayerJoined{}}` on success.
  """
  @spec join(Events.room_id(), Events.player_id()) :: call_result()
  def join(room_id, player_id) do
    GenServer.call(via_tuple(room_id), {:join, player_id})
  end

  @doc """
  Update a player's display name while the room is in the lobby.

  Returns
    `:ok` on success, `{:error, :player_not_found}` if the player ID is invalid, or
    `{:error, :room_not_in_lobby}` if the room is not in the lobby state.
  """
  @spec name(Events.room_id(), Events.player_id(), String.t()) :: call_result()
  def name(room_id, player_id, desired_name) do
    GenServer.call(via_tuple(room_id), {:name, player_id, desired_name})
  end

  @doc """
  Start the round.

  Returns
    `:ok` on success, `{:error, :room_not_in_lobby}` if the room is not in the lobby state, or
    `{:error, :not_room_admin}` if the caller is not the room admin.
  """
  @spec start(Events.room_id(), Events.player_id()) :: call_result()
  def start(room_id, player_id) do
    GenServer.call(via_tuple(room_id), {:start, player_id})
  end

  @impl true
  @spec init(Events.room_id()) :: {:ok, state()}
  def init(room_id) do
    {:ok, %__MODULE__{room_id: room_id}}
  end

  # Implementation

  @impl true
  def handle_call({:join, player_id}, _from, state) do
    case Map.fetch(state.players, player_id) do
      {:ok, player} ->
        updated_players = Map.put(state.players, player_id, %{player | connected: true})
        next_state = %{state | players: updated_players}
        joined_event = %Events.PlayerJoined{player_id: player_id, name: player.name}

        {:reply, {:ok, joined_event}, next_state}

      :error ->
        player_name = random_player_name()

        updated_players =
          Map.put(state.players, player_id, %{name: player_name, connected: true, wins: 0})

        next_state = %{state | players: updated_players, admin_id: state.admin_id || player_id}
        joined_event = %Events.PlayerJoined{player_id: player_id, name: player_name}

        :ok = PubSub.broadcast({:room, state.room_id}, joined_event)

        {:reply, {:ok, joined_event}, next_state}
    end
  end

  @impl true
  def handle_call({:name, _player_id, _desired_name}, _from, %{state: :in_game} = _state) do
    # TODO: Implement name change when room in in game handler
  end

  def handle_call({:name, _player_id, _desired_name}, _from, _state) do
    # TODO: Implement name change when room in lobby handler
  end

  @impl true
  def handle_call({:start, _player_id}, _from, %{state: :in_game} = _state) do
    # TODO: Implement start game when room already in game handler
  end

  def handle_call({:start, _player_id}, _from, %{admin_id: _admin_id} = _state) do
    # TODO: Implement start game when caller not admin handler
  end

  def handle_call({:start, _player_id}, _from, _state) do
    # TODO: Implement start game when caller is admin handler
  end

  defp random_player_name do
    "Player-" <> Nanoid.generate(4)
  end
end
