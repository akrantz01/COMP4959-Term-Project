defmodule Uno.PubSub do
  @moduledoc """
  Helpers for dispatching events along the PubSub broker
  """

  defp topic_name({:room, id}), do: "room:#{id}"
  defp topic_name({:game, id}), do: "game:#{id}"

  def subscribe(topic), do: Phoenix.PubSub.subscribe(__MODULE__, topic_name(topic))

  def unsubscribe(topic), do: Phoenix.PubSub.unsubscribe(__MODULE__, topic_name(topic))

  def broadcast(topic, message),
    do: Phoenix.PubSub.broadcast(__MODULE__, topic_name(topic), message)

  def broadcast_from(from, topic, message),
    do: Phoenix.PubSub.broadcast_from(__MODULE__, from, topic_name(topic), message)

  def local_broadcast(topic, message),
    do: Phoenix.PubSub.local_broadcast(__MODULE__, topic_name(topic), message)
end
