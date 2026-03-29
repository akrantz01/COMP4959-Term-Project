defmodule UnoWeb.DevtoolsLive do
  use UnoWeb, :live_view

  alias Uno.Events
  alias Uno.PubSub

  alias UnoWeb.Forms.{PublishEventForm, SubscriptionForm}
  alias UnoWeb.Forms.PublishEvent.{CardBuilderForm, EventSelectorForm, HandEntryBuilderForm}

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
       publish_card_builder_form: nil,
       publish_hand_list: [],
       publish_hand_entry_builder_form: nil
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
         socket
         |> assign(
           publish_event_type: event_type,
           publish_selector_form: EventSelectorForm.to_form(changeset)
         )
         |> reset_publish_builders()}

      {:error, changeset} ->
        {:noreply, assign(socket, publish_selector_form: EventSelectorForm.to_form(changeset))}
    end
  end

  # --- Publish form validation ---

  def handle_event("publish-change", params, socket) do
    event_type = socket.assigns.publish_event_type
    changeset = %{PublishEventForm.changeset(event_type, params["publish"]) | action: :validate}

    {:noreply,
     socket
     |> assign(publish_form: PublishEventForm.to_form(changeset, event_type))
     |> maybe_validate_card_builder(params["card_builder"], event_type)
     |> maybe_validate_hand_entry_builder(params["hand_entry_builder"])}
  end

  # --- Publish submit ---

  def handle_event("publish-submit", %{"publish" => params}, socket) do
    %{publish_event_type: event_type, publish_card_list: card_list, subscription: sub} =
      socket.assigns

    topic_kind = PublishEventForm.topic_kind(event_type)

    with :ok <- validate_subscription(sub, topic_kind),
         :ok <- validate_card_list(event_type, card_list),
         {:ok, data} <- PublishEventForm.parse(event_type, params) do
      event =
        PublishEventForm.build_event(
          event_type,
          data,
          card_list,
          socket.assigns.publish_hand_list
        )

      PubSub.broadcast({topic_kind, sub.id}, event)

      {:noreply,
       socket
       |> put_flash(:info, "Event published")
       |> reset_publish_builders()}
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
    mode = card_builder_mode(socket.assigns.publish_event_type)

    {:noreply,
     add_builder_item(
       socket,
       :publish_card_builder_form,
       :publish_card_list,
       CardBuilderForm.new(mode),
       &CardBuilderForm.to_form/1
     )}
  end

  def handle_event("remove-card", %{"index" => idx}, socket) do
    {:noreply, remove_builder_item(socket, :publish_card_list, idx)}
  end

  # --- Hand entry builder ---

  def handle_event("add-hand-entry", _params, socket) do
    {:noreply,
     add_builder_item(
       socket,
       :publish_hand_entry_builder_form,
       :publish_hand_list,
       HandEntryBuilderForm.new(),
       &HandEntryBuilderForm.to_form/1
     )}
  end

  def handle_event("remove-hand-entry", %{"index" => idx}, socket) do
    {:noreply, remove_builder_item(socket, :publish_hand_list, idx)}
  end

  # --- Pub/sub event receivers ---

  @event_sources %{
    Events.PlayerJoined => "Room",
    Events.PlayerLeft => "Room",
    Events.GameStarted => "Room",
    Events.GameEnded => "Room",
    Events.NextTurn => "Game",
    Events.CardsPlayed => "Game",
    Events.CardsDrawn => "Game"
  }

  def handle_info(%mod{} = msg, socket) when is_map_key(@event_sources, mod) do
    {:noreply,
     stream_insert(
       socket,
       :events,
       %{
         id: Nanoid.generate(),
         source: @event_sources[mod],
         content: inspect(msg, pretty: true, width: 0),
         timestamp: DateTime.utc_now()
       },
       at: 0
     )}
  end

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
    socket
    |> assign(
      publish_event_type: nil,
      publish_selector_form: EventSelectorForm.new()
    )
    |> reset_publish_builders()
  end

  defp reset_publish_builders(socket) do
    event_type = socket.assigns.publish_event_type

    assign(socket,
      publish_form: if(event_type, do: PublishEventForm.new(event_type)),
      publish_card_list: [],
      publish_card_builder_form: card_builder_for(event_type),
      publish_hand_list: [],
      publish_hand_entry_builder_form: hand_entry_builder_for(event_type)
    )
  end

  defp maybe_validate_card_builder(socket, nil, _event_type), do: socket

  defp maybe_validate_card_builder(socket, params, event_type) do
    mode = card_builder_mode(event_type)
    changeset = %{CardBuilderForm.changeset(params, mode) | action: :validate}
    assign(socket, publish_card_builder_form: CardBuilderForm.to_form(changeset))
  end

  defp maybe_validate_hand_entry_builder(socket, nil), do: socket

  defp maybe_validate_hand_entry_builder(socket, params) do
    changeset = %{HandEntryBuilderForm.changeset(params) | action: :validate}
    assign(socket, publish_hand_entry_builder_form: HandEntryBuilderForm.to_form(changeset))
  end

  defp add_builder_item(socket, form_key, list_key, fresh_form, to_form_fn) do
    case Ecto.Changeset.apply_action(socket.assigns[form_key].source, :insert) do
      {:ok, item} ->
        assign(socket, [{list_key, socket.assigns[list_key] ++ [item]}, {form_key, fresh_form}])

      {:error, changeset} ->
        assign(socket, [{form_key, to_form_fn.(changeset)}])
    end
  end

  defp remove_builder_item(socket, list_key, index) do
    index = String.to_integer(index)
    assign(socket, [{list_key, List.delete_at(socket.assigns[list_key], index)}])
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

  defp card_event?(type), do: type in ~w(cards_played cards_drawn)

  defp card_builder_for(type) do
    if card_event?(type), do: CardBuilderForm.new(card_builder_mode(type))
  end

  defp card_builder_mode("cards_drawn"), do: :drawn
  defp card_builder_mode(_), do: :played

  defp hand_entry_builder_for(type) do
    if card_event?(type), do: HandEntryBuilderForm.new()
  end
end
