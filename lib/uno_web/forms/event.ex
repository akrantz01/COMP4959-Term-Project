defmodule UnoWeb.Forms.Event do
  @moduledoc """
  A meta form used to publish events
  """

  @doc """
  Create a new, empty form
  """
  @callback new() :: struct()

  @doc """
  Returns a changeset for the given form struct and params
  """
  @callback changeset(struct :: term(), attrs :: map()) :: Ecto.Changeset.t()

  @doc """
  Converts a validated event into a domain event
  """
  @callback to_event(form :: term()) :: struct()

  @doc """
  Converts a domain event struct back into a params map compatible with changeset/2.
  Used for serializing received PubSub events as scenario JSON.
  """
  @callback from_event(event :: struct()) :: map()

  @forms %{
    "player_joined" => __MODULE__.PlayerJoined,
    "player_left" => __MODULE__.PlayerLeft,
    "game_started" => __MODULE__.GameStarted,
    "game_ended" => __MODULE__.GameEnded,
    "sync" => __MODULE__.Sync,
    "next_turn" => __MODULE__.NextTurn,
    "cards_played" => __MODULE__.CardsPlayed,
    "cards_drawn" => __MODULE__.CardsDrawn
  }

  def form(event), do: Map.fetch(@forms, event)

  @event_to_type %{
    Uno.Events.PlayerJoined => "player_joined",
    Uno.Events.PlayerLeft => "player_left",
    Uno.Events.GameStarted => "game_started",
    Uno.Events.GameEnded => "game_ended",
    Uno.Events.Sync => "sync",
    Uno.Events.NextTurn => "next_turn",
    Uno.Events.CardsPlayed => "cards_played",
    Uno.Events.CardsDrawn => "cards_drawn"
  }

  def event_type(%mod{}) when is_map_key(@event_to_type, mod),
    do: Map.fetch!(@event_to_type, mod)

  @room_events [
    "player_joined",
    "player_left",
    "game_started",
    "game_ended"
  ]
  @game_events [
    "sync",
    "next_turn",
    "cards_played",
    "cards_drawn"
  ]

  def events(%{room: room, game: game}),
    do: [
      "Room Events": Enum.map(@room_events, &{&1, !room}),
      "Game Events": Enum.map(@game_events, &{&1, !game})
    ]

  @topics %{
    "player_joined" => :room,
    "player_left" => :room,
    "game_started" => :room,
    "game_ended" => :room,
    "sync" => :game,
    "next_turn" => :game,
    "cards_played" => :game,
    "cards_drawn" => :game
  }

  def topic(event), do: Map.fetch!(@topics, event)

  def form_key(mod), do: mod |> Module.split() |> List.last() |> Macro.underscore()
end
