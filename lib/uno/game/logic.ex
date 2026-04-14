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
