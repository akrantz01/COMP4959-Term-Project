defmodule Uno.Room.Supervisor do
  @moduledoc """
  Supervisor for room processes
  """

  use DynamicSupervisor

  alias Uno.Room

  def start_link(_args) do
    DynamicSupervisor.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl true
  def init(:ok) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  # Public API

  @doc """
  Start a new room with the given `room_id` or a random one if not provided.

  Returns
    `{:ok, room_id, pid}` on success, or
    `{:error, :room_id_taken}` if the room ID is already in use
  """
  def start_room(room_id \\ Nanoid.generate()) do
    case Registry.lookup(Uno.Room.Registry, room_id) do
      [] ->
        case DynamicSupervisor.start_child(__MODULE__, {Room, room_id}) do
          {:ok, pid} -> {:ok, room_id, pid}
          {:error, {:already_started, pid}} -> {:ok, room_id, pid}
          error -> error
        end

      _ ->
        {:error, :room_id_taken}
    end
  end

  @doc """
  Stop the room with the given `room_id`.

  Returns
    `:ok` on success, or
    `{:error, :room_not_found}` if no room with the given ID exists.
  """
  def stop_room(room_id) do
    case Registry.lookup(Uno.Room.Registry, room_id) do
      [{pid, _value}] -> DynamicSupervisor.terminate_child(__MODULE__, pid)
      [] -> {:error, :room_not_found}
    end
  end
end
