defmodule Uno.Game.Logic do
  @moduledoc """
  The core UNO logic
  """
  @type colour :: :red | :green | :blue | :yellow
  @type card_type :: 0..9 | :reverse | :skip | :draw_2
  @type card_wild :: :wild | :wild_draw_4
  @type hand_card :: {colour(), card_type()} | card_wild()
  @type played_card :: {colour(), card_type()} | {card_wild(), colour()}

  @hand_size 7
  @type player_id :: String.t()
  @type player :: {player_id(), String.t()}
  @type direction :: :ltr | :rtl
  @type t :: %__MODULE__{
    sequence: non_neg_integer(),
    deck: [hand_card()],
    hands: %{player_id() => [hand_card()]},
    players: :queue.queue(player()),
    top_card: played_card() | nil,
    direction: direction()
  }

  defstruct sequence: 0,
            deck: [],
            hands: %{},
            players: :queue.new(),
            top_card: nil,
            direction: :ltr

  # task 1
  @spec generate_deck() :: [hand_card()]
  def generate_deck do
    colours = [:red, :green, :blue, :yellow]

    colour_cards =
      for colour <- colours do
        zeros = [{colour, 0}]

        duplicated =
          for type <- [1..9 |> Enum.to_list(), :reverse, :skip, :draw_2] |> List.flatten(),
              _copy <- 1..2 do
            {colour, type}
          end

        zeros ++ duplicated
      end

    wildcards = List.duplicate(:wild, 4) ++ List.duplicate(:wild_draw_4, 4)

    colour_cards |> List.flatten() |> Kernel.++(wildcards)
  end

  def shuffle_deck(deck) do
    deck |> Enum.shuffle()
  end

  # Task 2
  @spec init([player()]) :: t()
  def init(players) do

    deck = generate_deck() |> shuffle_deck()

    # Deals hands from the deck to each player
    {hands, deck} =
      Enum.reduce(players, {%{}, deck}, fn {player_id, _name}, {hands, remaining_deck} ->
        {cards, remaining_deck} = Enum.split(remaining_deck, @hand_size)
        hand = cards
        {Map.put(hands, player_id, hand), remaining_deck}
      end)

    # Flipping the first card (starting card)
    {top_card, deck} = flip_starting_card(deck)

    # initializes queue, the rules specifies a random player should join first.
    start_index = Enum.random(0..(length(players) - 1))
    rotated_players = Enum.drop(players, start_index) ++ Enum.take(players, start_index)
    players_queue = :queue.from_list(rotated_players)

    # Setting the game instance
    %__MODULE__{
      sequence: 0,
      deck: deck,
      hands: hands,
      players: players_queue,
      top_card: top_card,
      direction: :ltr
    }

  end

  defp flip_starting_card(deck) do
    {[card], rest} = Enum.split(deck, 1)

    case card do
      # Not allowed to start with a wild card - flips until we get a non-wild card
      wild when wild in [:wild, :wild_draw_4] ->
        # Put it at the bottom and try again
        flip_starting_card(rest ++ [wild])

      {colour, type} ->
        {{colour, type}, rest}
    end
  end

  # Task 3
  @spec current_turn(t()) :: player_id()
  def current_turn(%__MODULE__{players: players}) do
    {:value, {player_id, _name}} = :queue.peek(players)
    player_id
  end

end
