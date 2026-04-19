defmodule UnoWeb.RoomPresenceChannel do
  @moduledoc """
  Presence channel for tracking player connection status per room.
  """

  use UnoWeb, :channel

  alias UnoWeb.Presence

  @impl true
  def join("room_presence:" <> room_id, %{"player_id" => player_id}, socket)
      when is_binary(player_id) and byte_size(player_id) > 0 do
    socket =
      socket
      |> assign(:room_id, room_id)
      |> assign(:player_id, player_id)

    send(self(), :after_join)
    {:ok, socket}
  end

  def join("room_presence:" <> _room_id, _payload, _socket),
    do: {:error, %{reason: "player_id_required"}}

  @impl true
  def handle_info(:after_join, socket) do
    room_id = socket.assigns.room_id
    player_id = socket.assigns.player_id

    case Presence.track(socket, player_id, %{online_at: inspect(System.system_time(:second))}) do
      {:ok, _} ->
        case join_room(room_id, player_id) do
          {:ok, _player} ->
            push(socket, "presence_state", Presence.list(socket))
            {:noreply, socket}

          {:error, reason} ->
            {:stop, {:room_join_failed, reason}, socket}
        end

      {:error, reason} ->
        {:stop, {:presence_track_failed, reason}, socket}
    end
  end

  @impl true
  def terminate(_reason, socket) do
    room_id = socket.assigns[:room_id]
    player_id = socket.assigns[:player_id]

    if is_binary(room_id) and is_binary(player_id) do
      _ = Presence.untrack(socket, player_id)

      if final_presence_for_player?(socket, player_id) do
        _ = leave_room(room_id, player_id)
      end
    end

    :ok
  end

  defp join_room(room_id, player_id) do
    Uno.Room.join(room_id, player_id)
  catch
    :exit, {:noproc, _} -> {:error, :room_not_found}
    :exit, _reason -> {:error, :room_unavailable}
  end

  defp leave_room(room_id, player_id) do
    Uno.Room.leave(room_id, player_id)
  catch
    :exit, {:noproc, _} -> {:error, :room_not_found}
    :exit, _reason -> {:error, :room_unavailable}
  end

  defp final_presence_for_player?(socket, player_id) do
    case Presence.list(socket) do
      %{^player_id => %{metas: metas}} when is_list(metas) and metas != [] -> false
      _ -> true
    end
  end
end
