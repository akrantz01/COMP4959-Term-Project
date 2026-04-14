defmodule UnoWeb.PageController do
  use UnoWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end

  def create_room(conn, _params) do
    room_id =
      :crypto.strong_rand_bytes(4)
      |> Base.url_encode64(padding: false)
      |> binary_part(0, 6)
      |> String.upcase()

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
