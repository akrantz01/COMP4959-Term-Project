defmodule UnoWeb.DevtoolsLive do
  use UnoWeb, :live_view

  alias Uno.Events
  alias Uno.PubSub

  alias UnoWeb.Forms.{PublishEventForm, SubscriptionForm}
  alias UnoWeb.Forms.PublishEvent.{CardBuilderForm, EventSelectorForm}

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       subscription: %{id: nil, room: false, game: false},
       subscribe_form: SubscriptionForm.new()
     )
     |> assign(
       publish_event_type: nil,
       publish_selector_form: EventSelectorForm.new(),
       publish_form: nil,
       publish_card_list: [],
       publish_card_builder_form: nil
     )
     |> stream(:events, [], reset: true)}
  end

  # --- Subscription events ---

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
         )
         |> reset_publish()
         |> stream(:events, [], reset: true)}

      {:error, changeset} ->
        {:noreply, assign(socket, subscribe_form: SubscriptionForm.to_form(changeset))}
    end
  end

  # --- Publish event selection ---

  def handle_event("publish-select-event", %{"event_selector" => params}, socket) do
    case EventSelectorForm.parse(params) do
      {:ok, %{event_type: type}} when type in [nil, ""] ->
        {:noreply, reset_publish(socket)}

      {:ok, %{event_type: event_type}} ->
        changeset = %{EventSelectorForm.changeset(params) | action: :validate}

        {:noreply,
         assign(socket,
           publish_event_type: event_type,
           publish_selector_form: EventSelectorForm.to_form(changeset),
           publish_form: PublishEventForm.new(event_type),
           publish_card_list: [],
           publish_card_builder_form: card_builder_for(event_type)
         )}

      {:error, changeset} ->
        {:noreply, assign(socket, publish_selector_form: EventSelectorForm.to_form(changeset))}
    end
  end

  # --- Publish form validation ---

  def handle_event("publish-change", params, socket) do
    event_type = socket.assigns.publish_event_type

    changeset = %{PublishEventForm.changeset(event_type, params["publish"]) | action: :validate}
    form = PublishEventForm.to_form(changeset, event_type)

    socket = assign(socket, publish_form: form)

    socket =
      if cb_params = params["card_builder"] do
        cb_changeset = %{CardBuilderForm.changeset(cb_params) | action: :validate}
        assign(socket, publish_card_builder_form: CardBuilderForm.to_form(cb_changeset))
      else
        socket
      end

    {:noreply, socket}
  end

  # --- Publish submit ---

  def handle_event("publish-submit", %{"publish" => params}, socket) do
    %{publish_event_type: event_type, publish_card_list: card_list, subscription: sub} =
      socket.assigns

    topic_kind = PublishEventForm.topic_kind(event_type)

    with :ok <- validate_subscription(sub, topic_kind),
         :ok <- validate_card_list(event_type, card_list),
         {:ok, data} <- PublishEventForm.parse(event_type, params) do
      event = PublishEventForm.build_event(event_type, data, card_list)
      PubSub.broadcast({topic_kind, sub.id}, event)

      {:noreply,
       socket
       |> put_flash(:info, "Event published")
       |> assign(
         publish_form: PublishEventForm.new(event_type),
         publish_card_list: [],
         publish_card_builder_form: card_builder_for(event_type)
       )}
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        form = PublishEventForm.to_form(%{changeset | action: :validate}, event_type)
        {:noreply, assign(socket, publish_form: form)}

      {:error, message} ->
        {:noreply, put_flash(socket, :error, message)}
    end
  end

  # --- Card builder ---

  def handle_event("add-card", _params, socket) do
    case Ecto.Changeset.apply_action(socket.assigns.publish_card_builder_form.source, :insert) do
      {:ok, card} ->
        {:noreply,
         assign(socket,
           publish_card_list: socket.assigns.publish_card_list ++ [card],
           publish_card_builder_form: CardBuilderForm.new()
         )}

      {:error, changeset} ->
        {:noreply, assign(socket, publish_card_builder_form: CardBuilderForm.to_form(changeset))}
    end
  end

  def handle_event("remove-card", %{"index" => index}, socket) do
    index = String.to_integer(index)

    {:noreply,
     assign(socket, publish_card_list: List.delete_at(socket.assigns.publish_card_list, index))}
  end

  # --- Pub/sub event receivers ---

  def handle_info(%Events.PlayerJoined{} = msg, socket),
    do: {:noreply, insert_event(socket, "Room", msg)}

  def handle_info(%Events.PlayerLeft{} = msg, socket),
    do: {:noreply, insert_event(socket, "Room", msg)}

  def handle_info(%Events.GameStarted{} = msg, socket),
    do: {:noreply, insert_event(socket, "Room", msg)}

  def handle_info(%Events.GameEnded{} = msg, socket),
    do: {:noreply, insert_event(socket, "Room", msg)}

  def handle_info(%Events.NextTurn{} = msg, socket),
    do: {:noreply, insert_event(socket, "Game", msg)}

  def handle_info(%Events.CardsPlayed{} = msg, socket),
    do: {:noreply, insert_event(socket, "Game", msg)}

  def handle_info(%Events.CardsDrawn{} = msg, socket),
    do: {:noreply, insert_event(socket, "Game", msg)}

  # --- Private helpers ---

  defp sync_subscriptions(old, new) do
    sync_channel(:room, old.id, old.room, new.id, new.room)
    sync_channel(:game, old.id, old.game, new.id, new.game)
  end

  defp sync_channel(kind, old_id, old_on, new_id, new_on) do
    if old_id && old_on, do: PubSub.unsubscribe({kind, old_id})
    if new_id != "" && new_on, do: PubSub.subscribe({kind, new_id})
  end

  defp reset_publish(socket) do
    assign(socket,
      publish_event_type: nil,
      publish_selector_form: EventSelectorForm.new(),
      publish_form: nil,
      publish_card_list: [],
      publish_card_builder_form: nil
    )
  end

  defp validate_subscription(%{id: id}, _) when id in [nil, ""],
    do: {:error, "Enter a subscription ID first"}

  defp validate_subscription(sub, topic_kind) do
    if Map.get(sub, topic_kind),
      do: :ok,
      else: {:error, "Subscribe to the #{topic_kind} topic first"}
  end

  defp validate_card_list(type, []) when type in ~w(cards_played cards_drawn),
    do: {:error, "Add at least one card"}

  defp validate_card_list(_, _), do: :ok

  defp card_builder_for(type) when type in ~w(cards_played cards_drawn),
    do: CardBuilderForm.new()

  defp card_builder_for(_), do: nil

  defp insert_event(socket, source, event) do
    stream_insert(
      socket,
      :events,
      %{
        id: Nanoid.generate(),
        source: source,
        content: inspect(event, pretty: true, width: 0),
        timestamp: DateTime.utc_now()
      },
      at: 0
    )
  end
end
