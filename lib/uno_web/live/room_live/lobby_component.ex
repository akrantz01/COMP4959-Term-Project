defmodule UnoWeb.RoomLive.LobbyComponent do
  use Phoenix.LiveComponent

  def render(assigns) do
    connected_count = Enum.count(assigns.players, & &1.connected)
    assigns = assign(assigns, :connected_count, connected_count)

    ~H"""
    <div class="min-h-screen bg-[linear-gradient(180deg,#1f7ad6_0%,#2d97ea_50%,#62c9f5_100%)] px-6 py-10">
      <div class="mx-auto max-w-3xl">
        <div class="rounded-[2rem] border border-white/20 bg-white/12 p-8 shadow-2xl backdrop-blur-md">
          <div class="text-center">
            <div class="mx-auto flex h-20 w-20 items-center justify-center rounded-3xl bg-white/15 text-4xl text-white shadow-lg">
              🃏
            </div>

            <h1 class="mt-5 text-4xl font-black tracking-tight text-white">
              Lobby
            </h1>

            <p class="mt-2 text-white/85">
              Room Code: <span class="font-bold">{@room_id}</span>
            </p>
          </div>

          <div class="mt-8 grid gap-6">
            <div class="rounded-[1.5rem] bg-white/90 p-5 shadow-lg">
              <div class="mb-4 flex items-center justify-between">
                <h2 class="text-lg font-bold text-slate-900">Players</h2>
                <span class="rounded-full bg-slate-100 px-3 py-1 text-sm font-semibold text-slate-700">
                  {@connected_count} connected
                </span>
              </div>

              <div class="space-y-3">
                <%= for player <- @players do %>
                  <div class="flex items-center justify-between rounded-2xl bg-slate-50 px-4 py-3">
                    <div>
                      <div class="flex items-center gap-2">
                        <p class="font-semibold text-slate-900">{player.name}</p>
                        <%= if player.last_winner do %>
                          <span class="text-sm">👑</span>
                        <% end %>
                      </div>
                      <p class="text-sm text-slate-500">
                        Wins: {player.wins} • Losses: {player.losses}
                      </p>
                    </div>

                    <%= if player.connected do %>
                      <span class="rounded-full bg-green-100 px-3 py-1 text-sm font-medium text-green-700">
                        Connected
                      </span>
                    <% else %>
                      <span class="rounded-full bg-gray-200 px-3 py-1 text-sm font-medium text-gray-700">
                        Disconnected
                      </span>
                    <% end %>
                  </div>
                <% end %>
              </div>
            </div>

            <div class="rounded-[1.5rem] bg-white/90 p-5 shadow-lg">
              <h2 class="text-lg font-bold text-slate-900">Change Display Name</h2>

              <form phx-submit="update_name" class="mt-4 flex gap-3">
                <input
                  type="text"
                  name="player_name"
                  value={@player_name}
                  class="w-full rounded-2xl border border-slate-200 bg-white px-4 py-3 text-slate-800 outline-none"
                />

                <button
                  type="submit"
                  class="rounded-2xl bg-[linear-gradient(180deg,#91ef44_0%,#57c61e_100%)] px-5 py-3 font-bold text-white shadow-lg transition hover:scale-[1.02]"
                >
                  Save
                </button>
              </form>
            </div>

            <div class="rounded-[1.5rem] bg-white/90 p-5 shadow-lg">
              <h2 class="text-lg font-bold text-slate-900">Game Controls</h2>

              <%= if @is_admin do %>
                <button
                  phx-click="start_game"
                  disabled={@connected_count <= 2}
                  class="mt-4 w-full rounded-2xl bg-[linear-gradient(180deg,#ffe352_0%,#ffb400_100%)] px-6 py-3 text-lg font-black text-white shadow-lg transition hover:scale-[1.01] disabled:cursor-not-allowed disabled:opacity-60"
                >
                  Start Game
                </button>

                <p class="mt-3 text-sm text-slate-500">
                  Need at least 3 connected players.
                </p>
              <% else %>
                <p class="mt-3 text-sm text-slate-500">
                  Waiting for the room admin to start the game.
                </p>
              <% end %>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
