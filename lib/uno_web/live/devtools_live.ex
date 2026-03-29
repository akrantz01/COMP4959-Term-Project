defmodule UnoWeb.DevtoolsLive do
  use UnoWeb, :live_view

  alias Uno.PubSub
  alias UnoWeb.Forms.SubscriptionForm

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       subscription: %{id: nil, room: false, game: false},
       subscribe_form: SubscriptionForm.new()
     )}
  end

  def handle_event("subscribe-change", %{"subscription" => params}, socket) do
    changeset = SubscriptionForm.changeset(params)

    case SubscriptionForm.parse(params) do
      {:ok, data} ->
        sync_subscriptions(socket.assigns.subscription, data)

        {:noreply,
         socket
         |> assign(
           subscription: data,
           subscribe_form: SubscriptionForm.to_form(%{changeset | action: :validate})
         )}

      {:error, changeset} ->
        {:noreply, assign(socket, subscribe_form: SubscriptionForm.to_form(changeset))}
    end
  end

  defp sync_subscriptions(old, new) do
    sync_channel(:room, old.id, old.room, new.id, new.room)
    sync_channel(:game, old.id, old.game, new.id, new.game)
  end

  defp sync_channel(kind, old_id, old_on, new_id, new_on) do
    if old_id && old_on, do: PubSub.unsubscribe({kind, old_id})
    if new_id != "" && new_on, do: PubSub.subscribe({kind, new_id})
  end
end
