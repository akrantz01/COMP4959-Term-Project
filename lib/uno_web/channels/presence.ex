defmodule UnoWeb.Presence do
  @moduledoc """
  Presence tracker for room connection status.
  """

  use Phoenix.Presence,
    otp_app: :uno,
    pubsub_server: Uno.PubSub
end
