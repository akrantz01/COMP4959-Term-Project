defmodule Uno.Game.Logic do
  @moduledoc """
  The core UNO logic
  """
  @type colour :: :red | :green | :blue | :yellow
  @type card_type :: 0..9 | :reverse | :skip | :draw_2
  @type card_wild :: :wild | :wild_draw_4
  @type hand_card :: {colour(), card_type()} | card_wild()
  @type played_card :: {colour(), card_type()} | {card_wild(), colour()}

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
        hand = Enum.frequencies(cards)
        {Map.put(hands, player_id, hand), remaining_deck}
      end)

    # Flipping the first card (starting card)
    {top_card, deck} = flip_starting_card(deck)

    # initializes queue
    players_queue =
      players
      |> :queue.from_list()

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
    {[card | rest], deck} = Enum.split(deck, 1)

    case card do
      # Not allowed to start with a wild card - flips until we get a non-wild card
      wild when wild in [:wild, :wild_draw_4] ->
        # Put it at the bottom and try again
        flip_starting_card(rest ++ [wild])

      {colour, type} ->
        {{colour, type}, deck ++ rest}
    end
  end


end
