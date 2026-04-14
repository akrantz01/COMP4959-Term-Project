defmodule Uno.Room do
  @moduledoc """
  A collection of clients that are or will be playing the same game.
  """

  use GenServer

  defstruct room_id: nil,
            players: %{},
            status: :waiting,
            admin_player_id: nil,
            last_winner_player_id: nil

  ## PUBLIC API

  def start_link(room_id) do
    GenServer.start_link(__MODULE__, room_id, name: via(room_id))
  end

  def join(room_id, player_id, player_name) do
    ensure_started(room_id)
    GenServer.call(via(room_id), {:join, player_id, player_name})
  end

  def leave(room_id, player_id) do
    GenServer.cast(via(room_id), {:leave, player_id})
  end

  def start_game(room_id, player_id) do
    GenServer.call(via(room_id), {:start_game, player_id})
  end

  def rename_player(room_id, player_id, player_name) do
    GenServer.call(via(room_id), {:rename_player, player_id, player_name})
  end

  def get_state(room_id) do
    ensure_started(room_id)
    GenServer.call(via(room_id), :get_state)
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

  defp default_name(player_id) do
    "Player-" <> String.slice(player_id, 0, 4)
  end

  defp serialize_state(state) do
    %{
      room_id: state.room_id,
      players:
        state.players
        |> Map.values()
        |> Enum.sort_by(& &1.name),
      status: state.status,
      admin_player_id: state.admin_player_id,
      last_winner_player_id: state.last_winner_player_id
    }
  end

  defp broadcast_room_updated(state) do
    Phoenix.PubSub.broadcast(
      Uno.PubSub,
      "room:#{state.room_id}",
      {:room_updated, serialize_state(state)}
    )
  end

  ## SERVER

  @impl true
  def init(room_id) do
    {:ok,
     %__MODULE__{
       room_id: room_id,
       players: %{},
       status: :waiting,
       admin_player_id: nil,
       last_winner_player_id: nil
     }}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, serialize_state(state), state}
  end

  def handle_call({:join, player_id, player_name}, _from, state) do
    trimmed_name =
      player_name
      |> to_string()
      |> String.trim()

    final_name =
      if trimmed_name == "" do
        default_name(player_id)
      else
        trimmed_name
      end

    existing =
      Map.get(state.players, player_id, %{
        id: player_id,
        wins: 0,
        losses: 0
      })

    updated_player =
      existing
      |> Map.put(:id, player_id)
      |> Map.put(:name, final_name)
      |> Map.put(:connected, true)

    updated_state = %{
      state
      | players: Map.put(state.players, player_id, updated_player),
        admin_player_id: state.admin_player_id || player_id
    }

    broadcast_room_updated(updated_state)
    {:reply, {:ok, serialize_state(updated_state)}, updated_state}
  end

  def handle_call({:rename_player, player_id, player_name}, _from, state) do
    trimmed_name =
      player_name
      |> to_string()
      |> String.trim()

    cond do
      trimmed_name == "" ->
        {:reply, {:error, :invalid_name}, state}

      not Map.has_key?(state.players, player_id) ->
        {:reply, {:error, :player_not_found}, state}

      true ->
        updated_players =
          Map.update!(state.players, player_id, fn player ->
            Map.put(player, :name, trimmed_name)
          end)

        updated_state = %{state | players: updated_players}
        broadcast_room_updated(updated_state)
        {:reply, {:ok, serialize_state(updated_state)}, updated_state}
    end
  end

  def handle_call({:start_game, player_id}, _from, state) do
    connected_count =
      state.players
      |> Map.values()
      |> Enum.count(& &1.connected)

    cond do
      state.admin_player_id != player_id ->
        {:reply, {:error, :not_admin}, state}

      connected_count < 2 ->
        {:reply, {:error, :not_enough_players}, state}

      true ->
        updated_state = %{state | status: :playing}
        broadcast_room_updated(updated_state)
        {:reply, {:ok, serialize_state(updated_state)}, updated_state}
    end
  end

  @impl true
  def handle_cast({:leave, player_id}, state) do
    updated_players =
      case Map.get(state.players, player_id) do
        nil ->
          state.players

        player ->
          Map.put(state.players, player_id, %{player | connected: false})
      end

    updated_admin =
      if state.admin_player_id == player_id do
        updated_players
        |> Map.values()
        |> Enum.find(& &1.connected)
        |> case do
          nil -> nil
          player -> player.id
        end
      else
        state.admin_player_id
      end

    updated_state = %{state | players: updated_players, admin_player_id: updated_admin}
    broadcast_room_updated(updated_state)
    {:noreply, updated_state}
  end
end
