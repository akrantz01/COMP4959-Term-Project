defmodule Uno.Room do
  @moduledoc false
  use GenServer

  alias Uno.Events
  alias Uno.PubSub

  defstruct id: nil,
            state: :lobby,
            players: %{},
            admin_player_id: nil,
            last_winner_player_id: nil,
            games_played: 0

  def start_link(room_id) do
    GenServer.start_link(__MODULE__, room_id, name: via(room_id))
  end

  def create do
    room_id = generate_room_id()

    case Uno.RoomSupervisor.start_room(room_id) do
      {:ok, _pid} -> {:ok, room_id}
      {:error, {:already_started, _pid}} -> create()
      {:error, reason} -> {:error, reason}
    end
  end

  def exists?(room_id) do
    case Registry.lookup(Uno.RoomRegistry, room_id) do
      [{_pid, _value}] -> true
      [] -> false
    end
  end

  def get_state(room_id) do
    GenServer.call(via(room_id), :get_state)
  end

  def join(room_id, player_id, name) do
    GenServer.call(via(room_id), {:join, player_id, name})
  end

  def rename_player(room_id, player_id, name) do
    GenServer.call(via(room_id), {:rename_player, player_id, name})
  end

  def start_game(room_id, player_id) do
    GenServer.call(via(room_id), {:start_game, player_id})
  end

  def leave(room_id, player_id) do
    GenServer.call(via(room_id), {:leave, player_id})
  end

  def via(room_id) do
    {:via, Registry, {Uno.RoomRegistry, room_id}}
  end

  @impl true
  def init(room_id) do
    {:ok, %__MODULE__{id: room_id}}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  def handle_call({:join, player_id, name}, _from, state) do
    if state.state != :lobby do
      {:reply, {:error, :room_not_in_lobby}, state}
    else
      trimmed_name = String.trim(name)

      existing =
        Map.get(state.players, player_id, %{
          player_id: player_id,
          name: trimmed_name,
          connected: true,
          wins: 0,
          losses: 0
        })

      updated_player =
        existing
        |> Map.put(:name, trimmed_name)
        |> Map.put(:connected, true)

      updated_players = Map.put(state.players, player_id, updated_player)

      updated_state =
        if state.admin_player_id do
          %{state | players: updated_players}
        else
          %{state | players: updated_players, admin_player_id: player_id}
        end

      PubSub.broadcast({:room, state.id}, %Events.PlayerJoined{
        player_id: player_id,
        name: updated_player.name
      })

      {:reply, {:ok, updated_state}, updated_state}
    end
  end

  def handle_call({:rename_player, player_id, name}, _from, state) do
    cond do
      state.state != :lobby ->
        {:reply, {:error, :not_in_lobby}, state}

      String.trim(name) == "" ->
        {:reply, {:error, :invalid_name}, state}

      not Map.has_key?(state.players, player_id) ->
        {:reply, {:error, :player_not_found}, state}

      true ->
        trimmed_name = String.trim(name)

        updated_player =
          state.players
          |> Map.fetch!(player_id)
          |> Map.put(:name, trimmed_name)

        updated_players = Map.put(state.players, player_id, updated_player)
        updated_state = %{state | players: updated_players}

        {:reply, {:ok, updated_state}, updated_state}
    end
  end

  def handle_call({:start_game, player_id}, _from, state) do
    connected_count =
      state.players
      |> Map.values()
      |> Enum.count(& &1.connected)

    cond do
      state.state != :lobby ->
        {:reply, {:error, :already_started}, state}

      state.admin_player_id != player_id ->
        {:reply, {:error, :not_admin}, state}

      connected_count < 2 ->
        {:reply, {:error, :not_enough_players}, state}

      true ->
        updated_state = %{state | state: :in_game}

        PubSub.broadcast({:room, state.id}, %Events.GameStarted{
          room_id: state.id
        })

        {:reply, {:ok, updated_state}, updated_state}
    end
  end

  def handle_call({:leave, player_id}, _from, state) do
    case Map.get(state.players, player_id) do
      nil ->
        {:reply, :ok, state}

      player ->
        updated_player = %{player | connected: false}
        updated_players = Map.put(state.players, player_id, updated_player)
        updated_admin = next_admin_player_id(state, updated_players, player_id)

        updated_state = %{state | players: updated_players, admin_player_id: updated_admin}

        PubSub.broadcast({:room, state.id}, %Events.PlayerLeft{
          player_id: player_id
        })

        {:reply, :ok, updated_state}
    end
  end

  defp next_admin_player_id(state, updated_players, leaving_player_id) do
    if state.admin_player_id == leaving_player_id do
      updated_players
      |> Map.values()
      |> Enum.find(& &1.connected)
      |> case do
        nil -> nil
        player -> player.player_id
      end
    else
      state.admin_player_id
    end
  end

  defp generate_room_id do
    :crypto.strong_rand_bytes(4)
    |> Base.url_encode64(padding: false)
    |> binary_part(0, 6)
    |> String.upcase()
  end
end
