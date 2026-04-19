defmodule Uno.Events do
  @moduledoc """
  Shared event contract used by the Room, Game, and Client layers.

  This module defines the structs used for PubSub communication.

  ## PubSub Topics

  | Source | Name | Description |
  |--------|------|-------------|
  | Room | `room:${room_id}` | Events broadcast to all clients in a room |
  | Game | `game:${game_id}` | Events broadcast to all clients in a game |
  """

  @type room_id :: String.t()
  @type player_id :: String.t()
  @type colour :: :red | :green | :blue | :yellow
  @type card_type :: 0..9 | :reverse | :skip | :draw_2
  @type card_wild :: :wild | :wild_draw_4
  @type hand_card :: {colour(), card_type()} | card_wild()
  @type played_card :: {colour(), card_type()} | {card_wild(), colour()}
  @type direction :: :ltr | :rtl
  @type penalties :: %{player_id() => non_neg_integer()}
  @type chain :: %{
          type: :draw_2 | :wild_draw_4,
          amount: pos_integer()
        }

  ### Room -> Client events

  defmodule PlayerJoined do
    @moduledoc """
    A player has joined the room
    """

    @enforce_keys [:player_id, :name]
    defstruct [:player_id, :name]

    @type t :: %__MODULE__{
            player_id: String.t(),
            name: String.t()
          }
  end

  defmodule PlayerLeft do
    @moduledoc """
    A player has left the room
    """

    @enforce_keys [:player_id]
    defstruct [:player_id]

    @type t :: %__MODULE__{
            player_id: String.t()
          }
  end

  defmodule AdminChanged do
    @moduledoc """
    Added by Aarshdeep Vandal:
    The room has re-assigned the admin status to a new player
    """

    @enforce_keys [:new_admin_id]
    defstruct [:new_admin_id]

    @type t :: %__MODULE__{
            new_admin_id: String.t() | nil
          }
  end

  defmodule GameStarted do
    @moduledoc """
    The game was started by the room admin
    """

    @enforce_keys [:game_id]
    defstruct [:game_id]

    @type t :: %__MODULE__{
            game_id: String.t()
          }
  end

  defmodule GameEnded do
    @moduledoc """
    The game has ended.
    """

    @enforce_keys [:winner_id]
    defstruct [:winner_id]

    @type t :: %__MODULE__{
            winner_id: String.t()
          }
  end

  ### Game -> Client events

  defmodule Sync do
    @moduledoc """
    Synchronize the current game state with all the clients.
    """

    @enforce_keys [:sequence, :current_player_id, :top_card, :direction, :hands, :players]
    defstruct [
      :sequence,
      :current_player_id,
      :top_card,
      :direction,
      :hands,
      :players,
      vulnerable_player_id: nil,
      chain: nil
    ]

    @type t :: %__MODULE__{
            sequence: non_neg_integer(),
            current_player_id: Uno.Events.player_id(),
            top_card: Uno.Events.played_card(),
            direction: Uno.Events.direction(),
            hands: %{String.t() => %{Uno.Events.hand_card() => non_neg_integer()}},
            players: %{Uno.Events.player_id() => String.t()},
            vulnerable_player_id: Uno.Events.player_id() | nil,
            chain: Uno.Events.chain() | nil
          }
  end

  defmodule NextTurn do
    @moduledoc """
    The game has advanced to the next player's turn.
    """

    @enforce_keys [:sequence, :player_id, :top_card, :direction]
    defstruct [
      :sequence,
      :player_id,
      :top_card,
      :direction,
      vulnerable_player_id: nil,
      skipped: false,
      chain: nil
    ]

    @type t :: %__MODULE__{
            sequence: non_neg_integer(),
            player_id: Uno.Events.player_id(),
            top_card: Uno.Events.played_card(),
            direction: Uno.Events.direction(),
            vulnerable_player_id: Uno.Events.player_id() | nil,
            skipped: boolean(),
            chain: Uno.Events.chain() | nil
          }
  end

  defmodule CardsPlayed do
    @moduledoc """
    One or more cards have been played by a player.
    """

    @enforce_keys [:player_id, :played_cards, :hand]
    defstruct [:player_id, :played_cards, :hand]

    @type t :: %__MODULE__{
            player_id: Uno.Events.player_id(),
            played_cards: list(Uno.Events.played_card()),
            hand: %{Uno.Events.hand_card() => non_neg_integer()}
          }
  end

  defmodule CardsDrawn do
    @moduledoc """
    One or more cards were drawn by a player.
    """

    @enforce_keys [:player_id, :drawn_cards, :hand]
    defstruct [:player_id, :drawn_cards, :hand]

    @type t :: %__MODULE__{
            player_id: Uno.Events.player_id(),
            drawn_cards: list(Uno.Events.hand_card()),
            hand: %{Uno.Events.hand_card() => non_neg_integer()}
          }
  end
end
