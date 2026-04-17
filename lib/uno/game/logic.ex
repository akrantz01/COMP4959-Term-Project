defmodule Uno.Game.Logic do
  @moduledoc """
  The core UNO logic
  """
  @type colour :: :red | :green | :blue | :yellow
  @type card_type :: 0..9 | :reverse | :skip | :draw_2
  @type card_wild :: :wild | :wild_draw_4
  @type hand_card :: {colour(), card_type()} | card_wild()
  @type played_card :: {colour(), card_type()} | {card_wild(), colour()}
  @type chain_type :: :draw_2 | :wild_draw_4
  @type chain :: %{type: chain_type(), amount: pos_integer()}

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
        {Map.put(hands, player_id, cards), remaining_deck}
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

  # GL-5
  @spec playable_card?(hand_card(), played_card() | nil) :: boolean()
  defp playable_card?(_card, nil), do: false

  defp playable_card?(card, _top_card) when card in [:wild, :wild_draw_4], do: true

  defp playable_card?({colour, _type}, {:wild, active_colour}) do
    colour == active_colour
  end

  defp playable_card?({colour, _type}, {:wild_draw_4, active_colour}) do
    colour == active_colour
  end

  defp playable_card?({colour, type}, {top_colour, top_type}) do
    colour == top_colour or type == top_type
  end

  # Task 3
  @spec current_turn(t()) :: player_id()
  def current_turn(%__MODULE__{players: players}) do
    {:value, {player_id, _name}} = :queue.peek(players)
    player_id
  end

  # GL-4
  @spec player_hands(t()) :: %{player_id() => [hand_card()]}
  def player_hands(%__MODULE__{hands: hands}) do
    hands
  end

  # GL-6
  @spec next_playable_card(t(), player_id()) :: hand_card() | nil
  def next_playable_card(%__MODULE__{hands: hands, top_card: top_card}, player_id) do
    hands
    |> Map.get(player_id, [])
    |> Enum.find(fn card -> playable_card?(card, top_card) end)
  end

  # helper to count the card type
  @spec count_card_type([played_card()], card_type()) :: non_neg_integer()
  defp count_card_type(played_cards, type) do
    Enum.count(played_cards, fn
      {_colour, ^type} -> true
      _ -> false
    end)
  end

  # GL-7
  @spec play_cards(t(), player_id(), played_card()) ::
          {:ok, t()} | {:error, :not_your_turn | :card_not_in_hand | :card_not_playable}
  def play_cards(game, player_id, played_card) do
    with :ok <- check_turn(game, player_id),
         :ok <- check_in_hand(game, player_id, played_card),
         :ok <- check_playable(played_card, game.top_card) do
      game =
        game
        |> remove_from_hand(player_id, played_card)
        |> Map.put(:top_card, played_card)
        |> Map.put(:sequence, game.sequence + 1)
        |> advance_turn()

      {:ok, game}
    end
  end

  @spec check_turn(t(), player_id()) :: :ok | {:error, :not_your_turn}
  defp check_turn(game, player_id) do
    if current_turn(game) == player_id, do: :ok, else: {:error, :not_your_turn}
  end

  @spec check_in_hand(t(), player_id(), played_card()) :: :ok | {:error, :card_not_in_hand}
  defp check_in_hand(%__MODULE__{hands: hands}, player_id, played_card) do
    hand_card = to_hand_card(played_card)
    in_hand? = hands |> Map.get(player_id, []) |> Enum.member?(hand_card)
    if in_hand?, do: :ok, else: {:error, :card_not_in_hand}
  end

  @spec check_playable(played_card(), played_card() | nil) :: :ok | {:error, :card_not_playable}
  defp check_playable(played_card, top_card) do
    hand_card = to_hand_card(played_card)
    if playable_card?(hand_card, top_card), do: :ok, else: {:error, :card_not_playable}
  end

  # Converts a played_card() back to a hand_card() for hand lookup and playability checks.
  # e.g. {:wild, :red} -> :wild | {:red, 5} -> {:red, 5}
  @spec to_hand_card(played_card()) :: hand_card()
  defp to_hand_card({wild, _colour}) when wild in [:wild, :wild_draw_4], do: wild
  defp to_hand_card(card), do: card

  @spec remove_from_hand(t(), player_id(), played_card()) :: t()
  defp remove_from_hand(game, player_id, played_card) do
    hand_card = to_hand_card(played_card)

    updated_hand =
      game.hands
      |> Map.get(player_id, [])
      |> List.delete(hand_card)

    %{game | hands: Map.put(game.hands, player_id, updated_hand)}
  end

  @spec advance_turn(t()) :: t()
  defp advance_turn(%__MODULE__{players: players, direction: direction} = game) do
    {{:value, current}, rest} = :queue.out(players)

    new_players =
      case direction do
        :ltr -> :queue.in(current, rest)
        :rtl -> :queue.in_r(current, rest)
      end

    %{game | players: new_players}
  end

  # GL-8 (Helper function to flip direction)
  @spec apply_reverse(direction(), [played_card()]) :: {direction(), boolean()}
  def apply_reverse(direction, played_cards) do
    reverse_count = count_card_type(played_cards, :reverse)

    new_direction =
      if rem(reverse_count, 2) == 1 do
        flip_direction(direction)
      else
        direction
      end

    {new_direction, new_direction != direction}
  end

  @spec flip_direction(direction()) :: direction()
  def flip_direction(:ltr), do: :rtl
  def flip_direction(:rtl), do: :ltr

  # Gl-9 (Helper function to count the number of skips)
  @spec apply_skip([played_card()]) :: non_neg_integer()
  def apply_skip(played_cards) do
    count_card_type(played_cards, :skip)
  end

  # GL-10
  @spec apply_chain(chain() | nil, [played_card()]) ::
          {:ok, chain() | nil} | {:error, :mixed_chain}
  def apply_chain(chain, played_cards) do
    draw_2_count =
      Enum.count(played_cards, fn
        {_colour, :draw_2} -> true
        _ -> false
      end)

    wild_draw_4_count =
      Enum.count(played_cards, fn
        {:wild_draw_4, _colour} -> true
        _ -> false
      end)

    cond do
      draw_2_count > 0 and wild_draw_4_count > 0 ->
        {:error, :mixed_chain}

      draw_2_count > 0 ->
        apply_draw_2_chain(chain, draw_2_count)

      wild_draw_4_count > 0 ->
        apply_wild_draw_4_chain(chain, wild_draw_4_count)

      true ->
        {:ok, chain}
    end
  end

  @spec apply_draw_2_chain(chain() | nil, non_neg_integer()) ::
          {:ok, chain()} | {:error, :mixed_chain}
  def apply_draw_2_chain(nil, count) do
    {:ok, %{type: :draw_2, amount: count * 2}}
  end

  def apply_draw_2_chain(%{type: :draw_2, amount: amount}, count) do
    {:ok, %{type: :draw_2, amount: amount + count * 2}}
  end

  def apply_draw_2_chain(%{type: :wild_draw_4}, _count) do
    {:error, :mixed_chain}
  end

  @spec apply_wild_draw_4_chain(chain() | nil, non_neg_integer()) ::
          {:ok, chain()} | {:error, :mixed_chain}
  def apply_wild_draw_4_chain(nil, count) do
    {:ok, %{type: :wild_draw_4, amount: count * 4}}
  end

  def apply_wild_draw_4_chain(%{type: :wild_draw_4, amount: amount}, count) do
    {:ok, %{type: :wild_draw_4, amount: amount + count * 4}}
  end

  def apply_wild_draw_4_chain(%{type: :draw_2}, _count) do
    {:error, :mixed_chain}
  end

  # GL-11
  # Validates that a multi-card play is internally legal
  # same number/type for normal cards, or same wild type for wild cards.
  @spec valid_multi_play?([played_card()]) :: boolean()
  def valid_multi_play?([]), do: false
  def valid_multi_play?([_single_card]), do: true

  def valid_multi_play?(played_cards) do
    cond do
      all_same_normal_type?(played_cards) -> true
      all_same_wild_type?(played_cards) -> true
      true -> false
    end
  end

  @spec all_same_normal_type?([played_card()]) :: boolean()
  def all_same_normal_type?(played_cards) do
    case played_cards do
      [{first_colour, first_type} | rest] when first_colour in [:red, :green, :blue, :yellow] ->
        Enum.all?(rest, fn
          {colour, type} when colour in [:red, :green, :blue, :yellow] ->
            type == first_type

          _ ->
            false
        end)

      _ ->
        false
    end
  end

  @spec all_same_wild_type?([played_card()]) :: boolean()
  def all_same_wild_type?(played_cards) do
    case played_cards do
      [{first_wild_type, _first_colour} | rest] when first_wild_type in [:wild, :wild_draw_4] ->
        Enum.all?(rest, fn
          {wild_type, _colour} when wild_type in [:wild, :wild_draw_4] ->
            wild_type == first_wild_type

          _ ->
            false
        end)

      _ ->
        false
    end
  end
  # TODO: Temp stub just to let server compile
  @spec draw_card(t(), player_id()) :: {:ok, t(), hand_card(), :playable | :penalty_continue | :penalty_complete | :unplayable} | {:error, atom()}
  def draw_card(game, player_id) do
    if player_id do
      {:ok, game, {:red, 0}, :playable}
    else
      {:error, :invalid_player_id}
    end
  end
end
