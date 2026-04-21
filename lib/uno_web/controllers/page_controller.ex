defmodule UnoWeb.PageController do
  use UnoWeb, :controller

  alias Uno.Room

  def home(conn, _params) do
    render(conn, :home)
  end

  def create_room(conn, _params) do
    {:ok, room_id, _pid} = Room.Supervisor.start_room()

    redirect(conn, to: "/room/#{room_id}")
  end

  def join_room(conn, %{"room_id" => room_id}) do
    room_id = String.trim(room_id || "")

    if room_id == "" do
      conn
      |> put_flash(:error, "Please enter a room code.")
      |> redirect(to: "/")
    else
      case Room.Supervisor.lookup(room_id) do
        {:ok, _pid} -> redirect(conn, to: "/room/#{room_id}")
        {:error, :not_found} -> conn |> put_flash(:error, "Room not found!") |> redirect(to: "/")
      end
    end
  end
end
