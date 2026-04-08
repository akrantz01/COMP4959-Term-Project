defmodule UnoWeb.RoomLive.LobbyComponent do
  use Phoenix.LiveComponent

  def render(assigns) do
    ~H"""
    <div>
      <p>Status: {@status}</p>

      <h2>Players:</h2>
      <ul>
        <li :for={p <- @players}>
          {p}
        </li>
      </ul>

      <button phx-click="start_game">Start Game</button>
      <button phx-click="end_game">End Game</button>
    </div>
    """
  end
end
