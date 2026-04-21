defmodule Uno.Presence do
  @moduledoc """
  Presence tracker for room connection status.
  """

  alias Uno.Room

  use Phoenix.Presence,
    otp_app: :uno,
    pubsub_server: Uno.PubSub

  @impl true
  def init(_opts), do: {:ok, %{}}

  @impl true
  def handle_metas(topic, %{joins: joins, leaves: leaves}, presences, state) do
    for {player_id, _presence} <- joins do
      status =
        case Map.fetch(presences, player_id) do
          {:ok, [_one]} -> :online
          _ -> :tab_added
        end

      Room.update_connection_status(topic, player_id, status)
    end

    for {player_id, _presence} <- leaves do
      status = if(Map.has_key?(presences, player_id), do: :tab_removed, else: :offline)
      Room.update_connection_status(topic, player_id, status)
    end

    {:ok, state}
  end
end
