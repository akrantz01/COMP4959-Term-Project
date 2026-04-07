defmodule UnoWeb.RoomLive do
  use UnoWeb, :live_view

  alias Uno.PubSub
  alias Uno.Events
  alias UnoWeb.RoomLive.{GameComponent, LobbyComponent}

  def mount(%{"id" => id}, _session, socket) do
    if connected?(socket) do
      PubSub.subscribe({:room, id})
    end

    player_id = random_id()
    player_name = "Player-" <> String.slice(player_id, 0, 4)

    players = [
      %{
        player_id: player_id,
        name: player_name,
        connected: true,
        wins: 0,
        losses: 0,
        last_winner: false
      }
    ]

    if connected?(socket) do
      PubSub.broadcast({:room, id}, %Events.PlayerJoined{
        player_id: player_id,
        name: player_name
      })
    end

    {:ok,
     socket
     |> assign(:id, id)
     |> assign(:state, :lobby)
     |> assign(:player_id, player_id)
     |> assign(:player_name, player_name)
     |> assign(:is_admin, true)
     |> assign(:players, players)}
  end

  def handle_info(%Events.PlayerJoined{player_id: player_id, name: name}, socket) do
    players =
      add_or_update_player(socket.assigns.players, %{
        player_id: player_id,
        name: name,
        connected: true,
        wins: 0,
        losses: 0,
        last_winner: false
      })

    {:noreply, assign(socket, :players, players)}
  end

  def handle_info(%Events.PlayerLeft{player_id: player_id}, socket) do
    players =
      Enum.map(socket.assigns.players, fn player ->
        if player.player_id == player_id do
          %{player | connected: false}
        else
          player
        end
      end)

    {:noreply, assign(socket, :players, players)}
  end

  def handle_info(%Events.GameStarted{}, socket) do
    {:noreply, assign(socket, :state, :game)}
  end

  def handle_event("update_name", %{"player_name" => player_name}, socket) do
    player_name = String.trim(player_name)

    if player_name == "" do
      {:noreply, put_flash(socket, :error, "Name cannot be blank.")}
    else
      players =
        Enum.map(socket.assigns.players, fn player ->
          if player.player_id == socket.assigns.player_id do
            %{player | name: player_name}
          else
            player
          end
        end)

      {:noreply,
       socket
       |> assign(:player_name, player_name)
       |> assign(:players, players)
       |> put_flash(:info, "Display name updated.")}
    end
  end

  def handle_event("start_game", _params, socket) do
    connected_count = Enum.count(socket.assigns.players, & &1.connected)

    cond do
      not socket.assigns.is_admin ->
        {:noreply, put_flash(socket, :error, "Only the room admin can start the game.")}

      connected_count <= 2 ->
        {:noreply, put_flash(socket, :error, "Need more than 2 connected players.")}

      true ->
        PubSub.broadcast({:room, socket.assigns.id}, %Events.GameStarted{
          room_id: socket.assigns.id
        })

        {:noreply, socket}
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

  defp random_id do
    :crypto.strong_rand_bytes(6)
    |> Base.url_encode64(padding: false)
    |> binary_part(0, 8)
  end

  defp add_or_update_player(players, new_player) do
    case Enum.find(players, fn p -> p.player_id == new_player.player_id end) do
      nil ->
        players ++ [new_player]

      _existing ->
        Enum.map(players, fn player ->
          if player.player_id == new_player.player_id, do: new_player, else: player
        end)
    end
  end
end
