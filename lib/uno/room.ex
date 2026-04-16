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
          room_id: String.t(),
          state: room_state(),
          players: %{String.t() => player_meta()},
          admin_id: String.t() | nil,
          last_winner_id: String.t() | nil,
          games_played: non_neg_integer()
        }

  @typep state :: t()

  @doc """
  Starts the Uno.Room GenServer with the given room_id.
  """
  def start_link(room_id) do
    GenServer.start_link(__MODULE__, room_id, name: __MODULE__)
  end

  @impl true
  @spec init(Events.room_id()) :: {:ok, state()}
  def init(room_id) do
    {:ok, %__MODULE__{room_id: room_id}}
  end
end
