defmodule UnoWeb.Forms.PublishEventForm do
  @moduledoc """
  Coordinator for devtools event publishing forms.

  Maintains a registry of all publishable event types, provides generic
  changeset handling for simple events, and dispatches to dedicated form
  modules for complex ones (e.g. NextTurn).
  """

  import Ecto.Changeset

  alias UnoWeb.Forms.PublishEvent.NextTurnForm

  @colours ~w(red green blue yellow)
  @card_types ~w(0 1 2 3 4 5 6 7 8 9 reverse skip draw_2 wild wild_draw_4)
  @directions ~w(ltr rtl)
  @chain_types ~w(draw_2 wild_draw_4)

  def colours, do: @colours
  def card_types, do: @card_types
  def directions, do: @directions
  def chain_types, do: @chain_types

  @event_types %{
    "player_joined" => {:room, [player_id: :string, name: :string]},
    "player_left" => {:room, [player_id: :string]},
    "game_started" => {:room, [room_id: :string]},
    "game_ended" => {:room, [winner_id: :string]},
    "next_turn" => {:game, :custom},
    "cards_played" => {:game, [player_id: :string]},
    "cards_drawn" => {:game, [player_id: :string]}
  }

  @room_event_options [
    [key: "Player Joined", value: "player_joined"],
    [key: "Player Left", value: "player_left"],
    [key: "Game Started", value: "game_started"],
    [key: "Game Ended", value: "game_ended"]
  ]

  @game_event_options [
    [key: "Next Turn", value: "next_turn"],
    [key: "Cards Played", value: "cards_played"],
    [key: "Cards Drawn", value: "cards_drawn"]
  ]

  @doc "Returns event options with disabled state based on subscription."
  def event_options(%{room: room, game: game}) do
    [
      "Room Events": Enum.map(@room_event_options, &Keyword.put(&1, :disabled, !room)),
      "Game Events": Enum.map(@game_event_options, &Keyword.put(&1, :disabled, !game))
    ]
  end

  @doc "Returns the topic kind (:room or :game) for the given event type string."
  def topic_kind(event_type) do
    {kind, _} = Map.fetch!(@event_types, event_type)
    kind
  end

  def colour_options, do: Enum.map(@colours, &{String.capitalize(&1), &1})
  def card_type_options, do: Enum.map(@card_types, &{card_type_label(&1), &1})
  def direction_options, do: @directions |> Enum.map(&{direction_label(&1), &1})
  def chain_type_options, do: Enum.map(@chain_types, &{card_type_label(&1), &1})

  # --- Generic changeset for simple events ---

  def new(event_type) do
    case Map.fetch!(@event_types, event_type) do
      {_, :custom} -> NextTurnForm.new()
      {_, fields} -> fields |> generic_changeset() |> to_form(event_type)
    end
  end

  def changeset(event_type, params) do
    case Map.fetch!(@event_types, event_type) do
      {_, :custom} -> NextTurnForm.changeset(params)
      {_, fields} -> generic_changeset(fields, params)
    end
  end

  def to_form(changeset, event_type) do
    case Map.fetch!(@event_types, event_type) do
      {_, :custom} -> NextTurnForm.to_form(changeset)
      {_, _fields} -> Phoenix.Component.to_form(changeset, as: "publish")
    end
  end

  def parse(event_type, params) do
    case Map.fetch!(@event_types, event_type) do
      {_, :custom} -> NextTurnForm.parse(params)
      {_, fields} -> fields |> generic_changeset(params) |> apply_action(:insert)
    end
  end

  @doc """
  Builds the event struct from parsed form data and an optional card list.

  Card list items are maps like `%{"colour" => "red", "type" => "skip"}`.
  """
  def build_event(event_type, data, card_list \\ [], hand_list \\ [])

  def build_event("player_joined", data, _cards, _hand_list) do
    %Uno.Events.PlayerJoined{player_id: data.player_id, name: data.name}
  end

  def build_event("player_left", data, _cards, _hand_list) do
    %Uno.Events.PlayerLeft{player_id: data.player_id}
  end

  def build_event("game_started", data, _cards, _hand_list) do
    %Uno.Events.GameStarted{room_id: data.room_id}
  end

  def build_event("game_ended", data, _cards, _hand_list) do
    %Uno.Events.GameEnded{winner_id: data.winner_id}
  end

  def build_event("next_turn", data, _cards, _hand_list) do
    NextTurnForm.to_event(data)
  end

  def build_event("cards_played", data, cards, hand_list) do
    %Uno.Events.CardsPlayed{
      player_id: data.player_id,
      played_cards: Enum.map(cards, &to_played_card/1),
      hand: build_hand(hand_list)
    }
  end

  def build_event("cards_drawn", data, cards, hand_list) do
    %Uno.Events.CardsDrawn{
      player_id: data.player_id,
      drawn_cards: Enum.map(cards, &to_hand_card/1),
      hand: build_hand(hand_list)
    }
  end

  # --- Private helpers ---

  defp build_hand(hand_list) do
    Map.new(hand_list, fn entry ->
      {to_hand_card(%{colour: entry.colour, type: entry.type}), entry.count}
    end)
  end

  defp generic_changeset(fields, params \\ %{}) do
    types = Map.new(fields)
    defaults = Map.new(fields, fn {k, _} -> {k, ""} end)

    {defaults, types}
    |> cast(params, Map.keys(types))
    |> validate_required(Map.keys(types))
  end

  defp card_type_label("reverse"), do: "Reverse"
  defp card_type_label("skip"), do: "Skip"
  defp card_type_label("draw_2"), do: "Draw 2"
  defp card_type_label("wild"), do: "Wild"
  defp card_type_label("wild_draw_4"), do: "Wild Draw 4"
  defp card_type_label(n), do: n

  defp direction_label("ltr"), do: "Left to Right"
  defp direction_label("rtl"), do: "Right to Left"

  @doc false
  def to_played_card(%{type: type, colour: colour})
      when type in ~w(wild wild_draw_4) do
    {String.to_existing_atom(type), String.to_existing_atom(colour)}
  end

  def to_played_card(%{type: type, colour: colour})
      when type in ~w(0 1 2 3 4 5 6 7 8 9) do
    {String.to_existing_atom(colour), String.to_integer(type)}
  end

  def to_played_card(%{type: type, colour: colour}) do
    {String.to_existing_atom(colour), String.to_existing_atom(type)}
  end

  @doc false
  def to_hand_card(%{type: type}) when type in ~w(wild wild_draw_4) do
    String.to_existing_atom(type)
  end

  def to_hand_card(card), do: to_played_card(card)
end
