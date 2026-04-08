defmodule UnoWeb.RoomLive do
  use UnoWeb, :live_view

  alias Uno.PubSub
  alias Uno.Room
  alias Uno.Events
  alias UnoWeb.RoomLive.{GameComponent, LobbyComponent}

  def mount(%{"id" => id}, session, socket) do
    player_id = session["player_id"]

    cond do
      is_nil(player_id) ->
        {:ok,
         socket
         |> put_flash(:error, "Missing player session.")
         |> redirect(to: "/")}

      not Room.exists?(id) ->
        {:ok,
         socket
         |> put_flash(:error, "Room does not exist.")
         |> redirect(to: "/")}

      true ->
        if connected?(socket) do
          PubSub.subscribe({:room, id})
        end

        player_name = default_player_name(player_id)

        case Room.join(id, player_id, player_name) do
          {:ok, joined_state} ->
            {:ok,
             socket
             |> assign(:id, id)
             |> assign(:state, joined_state.state)
             |> assign(:player_id, player_id)
             |> assign(:player_name, get_in(joined_state.players, [player_id, :name]))
             |> assign(:is_admin, joined_state.admin_player_id == player_id)
             |> assign(:players, decorate_players(joined_state))
             |> assign(:last_winner_player_id, joined_state.last_winner_player_id)}

          {:error, :room_not_in_lobby} ->
            {:ok,
             socket
             |> put_flash(:error, "Room is already in game.")
             |> redirect(to: "/")}

          {:error, _} ->
            {:ok,
             socket
             |> put_flash(:error, "Could not join room.")
             |> redirect(to: "/")}
        end
    end
  end

  def handle_info(%Events.PlayerJoined{}, socket) do
    room_state = Room.get_state(socket.assigns.id)

    {:noreply,
     socket
     |> assign(:players, decorate_players(room_state))
     |> assign(:is_admin, room_state.admin_player_id == socket.assigns.player_id)
     |> assign(:state, room_state.state)}
  end

  def handle_info(%Events.PlayerLeft{}, socket) do
    room_state = Room.get_state(socket.assigns.id)

    {:noreply,
     socket
     |> assign(:players, decorate_players(room_state))
     |> assign(:is_admin, room_state.admin_player_id == socket.assigns.player_id)
     |> assign(:state, room_state.state)}
  end

  def handle_info(%Events.GameStarted{}, socket) do
    room_state = Room.get_state(socket.assigns.id)

    {:noreply,
     socket
     |> assign(:state, room_state.state)
     |> assign(:players, decorate_players(room_state))
     |> assign(:is_admin, room_state.admin_player_id == socket.assigns.player_id)}
  end

  def handle_event("update_name", %{"player_name" => player_name}, socket) do
    case Room.rename_player(socket.assigns.id, socket.assigns.player_id, player_name) do
      {:ok, room_state} ->
        {:noreply,
         socket
         |> assign(:player_name, get_in(room_state.players, [socket.assigns.player_id, :name]))
         |> assign(:players, decorate_players(room_state))
         |> put_flash(:info, "Display name updated.")}

      {:error, :invalid_name} ->
        {:noreply, put_flash(socket, :error, "Name cannot be blank.")}

      {:error, :not_in_lobby} ->
        {:noreply, put_flash(socket, :error, "Name can only be changed in the lobby.")}

      _ ->
        {:noreply, put_flash(socket, :error, "Could not update display name.")}
    end
  end

  def handle_event("start_game", _params, socket) do
    case Room.start_game(socket.assigns.id, socket.assigns.player_id) do
      {:ok, room_state} ->
        {:noreply, assign(socket, :state, room_state.state)}

      {:error, :not_admin} ->
        {:noreply, put_flash(socket, :error, "Only the room admin can start the game.")}

      {:error, :not_enough_players} ->
        {:noreply, put_flash(socket, :error, "Need at least 2 connected players.")}

      _ ->
        {:noreply, put_flash(socket, :error, "Could not start game.")}
    end
  end

  def render(assigns) do
    ~H"""
    <.live_component
      :if={@state == :lobby}
      module={LobbyComponent}
      id="lobby"
      room_id={@id}
      players={@players}
      player_name={@player_name}
      is_admin={@is_admin}
    />

    <.live_component :if={@state == :game} module={GameComponent} id="game" />
    """
  end

  defp default_player_name(player_id) do
    "Player-" <> String.slice(player_id, 0, 4)
  end

  defp decorate_players(room_state) do
    Enum.map(Map.values(room_state.players), fn player ->
      Map.put(player, :last_winner, room_state.last_winner_player_id == player.player_id)
    end)
  end
end
