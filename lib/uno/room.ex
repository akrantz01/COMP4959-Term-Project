defmodule Uno.Room do
  @moduledoc """
  Exposes an 'Uno.Room' for clients to connect with.

  Handles room creation, player joining/leaving, and game initiation.

  The room state includes:
  - `room_id`: Unique identifier for the room.
  - `players`: List of player IDs currently in the room.
  - `admin_id`: Player ID of the room admin (first to join).
  - `is_started`: Boolean indicating if the game has started.
  """

  use GenServer

  alias Uno.Events, as: Events

  @enforce_keys [:room_id]
  defstruct [:room_id, players: [], admin_id: nil, is_started: false]

  @typedoc """
  The type definition for the Uno.Room struct.
  """
  @type t :: %__MODULE__{
          room_id: Events.room_id(),
          players: list(Events.player_id()),
          admin_id: Events.player_id() | nil,
          is_started: boolean()
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
