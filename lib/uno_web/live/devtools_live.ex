defmodule UnoWeb.DevtoolsLive do
  use UnoWeb, :live_view

  alias Uno.Events
  alias Uno.PubSub

  alias UnoWeb.Forms.{SubscriptionForm, Event}

  def mount(params, _session, socket) do
    {:ok,
     socket
     |> subscribe(params)
     |> reset_publish()
     |> stream(:events, [], reset: true)
     |> assign(scenario_events: [], publish_tab: :event)}
  end

  # --- Subscription events ---

  def handle_event("subscribe-change", %{"subscription" => params}, socket),
    do: {:noreply, subscribe(socket, params)}

  # --- Publish event navigation ---

  def handle_event("publish-tab-change", %{"tab" => "event"}, socket),
    do: {:noreply, assign(socket, :publish_tab, :event)}

  def handle_event("publish-tab-change", %{"tab" => "scenario"}, socket),
    do: {:noreply, assign(socket, :publish_tab, :scenario)}

  def handle_event("publish-select-event", %{"type" => type}, socket) do
    case Event.form(type) do
      {:ok, mod} ->
        data = mod.new()

        {:noreply,
         assign(socket,
           publish_event_type: type,
           publish_form_module: mod,
           publish_form_data: data,
           publish_form: mod.changeset(data, %{}) |> to_form()
         )}

      :error ->
        {:noreply, put_flash(socket, :error, "Unknown event type: #{type}")}
    end
  end

  # --- Event publishing ---

  def handle_event("publish-validate", unsigned_params, socket) do
    %{publish_form_module: mod, publish_form_data: data} = socket.assigns
    params = Map.get(unsigned_params, Event.form_key(mod), %{})

    changeset = mod.changeset(data, params)

    {:noreply,
     assign(socket,
       publish_form_data: Ecto.Changeset.apply_changes(changeset),
       publish_form: to_form(changeset, action: :validate)
     )}
  end

  def handle_event("publish-submit", unsigned_params, socket) do
    %{
      publish_event_type: type,
      publish_form_module: mod,
      publish_form_data: data,
      subscription: subscription
    } =
      socket.assigns

    params = Map.get(unsigned_params, Event.form_key(mod), %{})

    case mod.changeset(data, params) |> Ecto.Changeset.apply_action(:insert) do
      {:ok, validated} ->
        PubSub.broadcast({Event.topic(type), subscription.id}, mod.to_event(validated))

        {:noreply,
         socket
         |> put_flash(:info, "Published #{event_name(type)} event!")
         |> reset_publish()}

      {:error, changeset} ->
        {:noreply, assign(socket, publish_form: to_form(changeset))}
    end
  end

  # --- Scenario handling ---

  def handle_event("scenario-change", _params, socket), do: {:noreply, socket}

  def handle_event("scenario-run", _params, %{assigns: %{replaying: true}} = socket),
    do: {:noreply, socket}

  def handle_event("scenario-run", _params, socket) do
    result =
      consume_uploaded_entries(socket, :scenario, fn %{path: path}, _entry ->
        {:ok, File.read!(path)}
      end)

    case result do
      [json] ->
        with {:ok, decoded} <- Jason.decode(json),
             {:ok, validated} <- validate_scenario(decoded, socket.assigns.subscription) do
          IO.inspect(validated) # TODO: replay all events in sequence
          {:noreply, assign(socket, replaying: true, publish_tab: :scenario)}
        else
          {:error, reason} when is_exception(reason) ->
            {:noreply,
             put_flash(socket, :error, "Invalid scenario JSON: #{Exception.message(reason)}")}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Scenario error: #{reason}")}
        end

      [] ->
        {:noreply, put_flash(socket, :error, "No file uploaded")}
    end
  end

  # --- Pub/sub event receivers ---

  @event_sources %{
    Events.PlayerJoined => "Room",
    Events.PlayerLeft => "Room",
    Events.GameStarted => "Room",
    Events.GameEnded => "Room",
    Events.Sync => "Sync",
    Events.NextTurn => "Game",
    Events.CardsPlayed => "Game",
    Events.CardsDrawn => "Game"
  }

  def handle_info(%mod{} = msg, socket) when is_map_key(@event_sources, mod) do
    timestamp = DateTime.utc_now()

    {:noreply,
     socket
     |> update(:scenario_events, &[%{event: msg, timestamp: timestamp} | &1])
     |> stream_insert(
       :events,
       %{
         id: Nanoid.generate(),
         source: @event_sources[mod],
         content: inspect(msg, pretty: true, width: 0),
         timestamp: timestamp
       },
       at: 0
     )}
  end

  # --- Private helpers ---

  defp subscribe(socket, params) do
    changeset = SubscriptionForm.changeset(params)

    case SubscriptionForm.parse(params) do
      {:ok, data} ->
        case socket.assigns do
          %{subscription: old} ->
            sync_channel(:room, old.id, old.room, data.id, data.room)
            sync_channel(:game, old.id, old.game, data.id, data.game)

          _ ->
            sync_channel(:room, nil, nil, data.id, data.room)
            sync_channel(:game, nil, nil, data.id, data.game)
        end

        socket
        |> assign(
          subscription: data,
          subscribe_form: SubscriptionForm.to_form(%{changeset | action: :validate}),
          scenario_events: []
        )
        |> reset_publish()
        |> stream(:events, [], reset: true)

      {:error, changeset} ->
        socket
        |> assign_new(:subscription, fn -> %{id: nil, room: false, game: false} end)
        |> assign(:subscribe_form, SubscriptionForm.to_form(changeset))
    end
  end

  defp sync_channel(kind, old_id, old_on, new_id, new_on) do
    if old_id && old_on, do: PubSub.unsubscribe({kind, old_id})
    if new_id != "" && new_on, do: PubSub.subscribe({kind, new_id})
  end

  defp reset_publish(socket) do
    assign(socket,
      publish_event_type: nil,
      publish_form_module: nil,
      publish_form_data: nil,
      publish_form: nil
    )
  end

  defp validate_scenario(entries, subscription) do
    if(is_list(entries), do: entries, else: [entries])
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {entry, idx}, {:ok, acc} ->
      validate_scenario_event(idx, entry, subscription, acc)
    end)
    |> case do
      {:ok, acc} -> {:ok, Enum.reverse(acc)}
      error -> error
    end
  end

  defp validate_scenario_event(idx, entry, subscription, acc) do
    with %{"event" => type} <- entry,
         delay_ms = if(idx == 0, do: 0, else: Map.get(entry, "delay_ms", 0)),
         params = Map.get(entry, "params", %{}),
         {:ok, mod} <- Event.form(type),
         {:ok, validated} <-
           mod.changeset(mod.new(), params) |> Ecto.Changeset.apply_action(:insert) do
      topic = {Event.topic(type), subscription.id}

      {:cont, {:ok, [{delay_ms, topic, mod.to_event(validated)} | acc]}}
    else
      _ -> {:halt, {:error, "invalid entry at index #{idx}"}}
    end
  end

  defp event_name(key) when is_atom(key), do: event_name(Atom.to_string(key))

  defp event_name(key) when is_binary(key),
    do: String.split(key, "_") |> Enum.map_join(" ", &String.capitalize/1)

  attr :form, Phoenix.HTML.Form, required: true

  defp card_inputs(assigns) do
    ~H"""
    <div class="flex gap-2">
      <.input
        field={@form[:type]}
        type="select"
        label="Type"
        prompt="Select..."
        options={card_types()}
      />
      <.input
        field={@form[:colour]}
        type="select"
        label="Colour"
        prompt="Select..."
        options={card_colours()}
      />
    </div>
    """
  end

  attr :form, Phoenix.HTML.Form, required: true
  attr :show, :boolean, required: true

  defp chain_fieldset(assigns) do
    ~H"""
    <fieldset class="border p-4 rounded">
      <legend>Chain (optional)</legend>
      <.input
        field={@form[:has_chain]}
        type="checkbox"
        class="toggle"
        label="Has chain?"
      />
      <.inputs_for
        :let={chain}
        :if={@show}
        field={@form[:chain]}
      >
        <div class="flex gap-2">
          <.input
            field={chain[:type]}
            type="select"
            label="Type"
            options={~w(draw_2 wild_draw_4)}
            prompt="None"
          />
          <.input field={chain[:amount]} type="number" label="Amount" />
        </div>
      </.inputs_for>
    </fieldset>
    """
  end

  attr :form, Phoenix.HTML.Form, required: true

  defp top_card_fieldset(assigns) do
    ~H"""
    <fieldset class="border p-4 rounded">
      <legend>Top Card</legend>
      <.inputs_for :let={tc} field={@form[:top_card]}>
        <.card_inputs form={tc} />
      </.inputs_for>
    </fieldset>
    """
  end

  attr :form, Phoenix.HTML.Form, required: true
  attr :field, :atom, required: true
  attr :sort, :atom, required: true
  attr :drop, :atom, required: true
  attr :label, :string, required: true
  attr :add_label, :string, required: true
  slot :item, required: true
  slot :actions

  defp embed_list(assigns) do
    ~H"""
    <fieldset class="border p-4 rounded space-y-2">
      <legend>{@label}</legend>
      <input type="hidden" name={"#{@form[@sort].name}[]"} />
      <input type="hidden" name={"#{@form[@drop].name}[]"} />

      <.inputs_for :let={f} field={@form[@field]}>
        <input type="hidden" name={"#{@form[@sort].name}[]"} value={f.index} />
        <div class="flex items-center gap-2">
          {render_slot(@item, f)}
          <.button
            name={"#{@form[@drop].name}[]"}
            value={f.index}
            phx-click={JS.dispatch("change")}
          >
            ✕
          </.button>
        </div>
      </.inputs_for>

      <div class="flex justify-between">
        <.button
          type="button"
          name={"#{@form[@sort].name}[]"}
          value="new"
          phx-click={JS.dispatch("change")}
        >
          + {@add_label}
        </.button>
        {render_slot(@actions)}
      </div>
    </fieldset>
    """
  end

  defp card_colours(),
    do: [{"Red", "red"}, {"Green", "green"}, {"Blue", "blue"}, {"Yellow", "yellow"}]

  defp card_types(),
    do: [
      "0",
      "1",
      "2",
      "3",
      "4",
      "5",
      "6",
      "7",
      "8",
      "9",
      {"Reverse", "reverse"},
      {"Skip", "skip"},
      {"Draw 2", "draw_2"},
      {"Wild", "wild"},
      {"Wild Draw 4", "wild_draw_4"}
    ]
end
