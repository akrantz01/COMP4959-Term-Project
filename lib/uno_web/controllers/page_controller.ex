defmodule UnoWeb.PageController do
  use UnoWeb, :controller

  alias Uno.Room

  def home(conn, _params) do
    player_id = get_or_create_player_id(conn)

    conn
    |> put_session(:player_id, player_id)
    |> render(:home)
  end

  def create_room(conn, _params) do
    case Room.create() do
      {:ok, room_id} ->
        redirect(conn, to: "/room/#{room_id}")

      {:error, _reason} ->
        conn
        |> put_flash(:error, "Could not create room.")
        |> redirect(to: "/")
    end
  end

  def join_room(conn, %{"room_id" => room_id}) do
    room_id = String.trim(room_id || "")

    cond do
      room_id == "" ->
        conn
        |> put_flash(:error, "Please enter a room code.")
        |> redirect(to: "/")

      not Room.exists?(room_id) ->
        conn
        |> put_flash(:error, "Room does not exist.")
        |> redirect(to: "/")

      true ->
        case Room.get_state(room_id) do
          %{state: :lobby} ->
            redirect(conn, to: "/room/#{room_id}")

          _ ->
            conn
            |> put_flash(:error, "Room can only be joined while in the lobby.")
            |> redirect(to: "/")
        end
    end
  end

  defp get_or_create_player_id(conn) do
    get_session(conn, :player_id) ||
      :crypto.strong_rand_bytes(8)
      |> Base.url_encode64(padding: false)
      |> binary_part(0, 10)
  end
end
