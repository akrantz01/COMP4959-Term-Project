defmodule Uno.Room do
  @moduledoc """
  Here is the logic to process user join, leave, start game, and end game
  """
  use GenServer

  ## PUBLIC API

  def start_link(room_id) do
    GenServer.start_link(__MODULE__, room_id, name: via(room_id))
  end

  def join(room_id, player_id) do
    ensure_started(room_id)
    GenServer.call(via(room_id), {:join, player_id})
  end

  def leave(room_id, player_id) do
    GenServer.cast(via(room_id), {:leave, player_id})
  end

  def start_game(room_id) do
    GenServer.cast(via(room_id), :start_game)
  end

  def end_game(room_id) do
    GenServer.cast(via(room_id), :end_game)
  end

  ## INTERNAL

  defp via(room_id) do
    {:via, Registry, {Uno.RoomRegistry, room_id}}
  end

  defp ensure_started(room_id) do
    case Registry.lookup(Uno.RoomRegistry, room_id) do
      [] -> start_link(room_id)
      _ -> :ok
    end
  end

  ## SERVER

  def init(room_id) do
    {:ok, %{room_id: room_id, players: [], status: :waiting}}
  end

  def handle_call({:join, player_id}, _from, state) do
    players = Enum.uniq([player_id | state.players])

    broadcast(state.room_id, :player_joined, player_id)

    {:reply, :ok, %{state | players: players}}
  end

  def handle_cast({:leave, player_id}, state) do
    players = List.delete(state.players, player_id)

    broadcast(state.room_id, :player_left, player_id)

    {:noreply, %{state | players: players}}
  end

  def handle_cast(:start_game, state) do
    broadcast(state.room_id, :game_started, %{})
    {:noreply, %{state | status: :playing}}
  end

  def handle_cast(:end_game, state) do
    broadcast(state.room_id, :game_ended, %{})
    {:noreply, %{state | status: :ended}}
  end

  defp broadcast(room_id, event, payload) do
    Phoenix.PubSub.broadcast(
      Uno.PubSub,
      "room:#{room_id}",
      {event, payload}
    )
  end
end
