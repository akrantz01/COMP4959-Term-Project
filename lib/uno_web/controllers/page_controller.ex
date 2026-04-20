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
      redirect(conn, to: "/room/#{room_id}")
    end
  end
end
