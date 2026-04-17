defmodule Uno.Game.ServerTest do
  use ExUnit.Case, async: false

  alias Uno.Game.{Server, Logic}
  alias Uno.Events

  # Injects a known top_card and hand so tests are deterministic.
  # top_card: {:red, 3}
  # current player's hand: [{:red, 5}, {:red, 0}, :wild, {:blue, 3}, {:green, 3}]
  # All five cards are playable (red matches colour; {:blue,3}/{:green,3} match number; :wild always)
  setup do
    room_id = "test-#{:erlang.unique_integer([:positive])}"
    {:ok, pid} = Server.start_link(room_id, [])

    players = [{"p1", "Alice"}, {"p2", "Bob"}]
    logic = Logic.init(players)
    current = Logic.current_turn(logic)

    logic = %{
      logic
      | hands: Map.put(logic.hands, current, [{:red, 5}, {:red, 0}, :wild, {:blue, 3}, {:green, 3}]),
        top_card: {:red, 3}
    }

    :sys.replace_state(pid, fn state -> %{state | logic_state: logic} end)

    Uno.PubSub.subscribe({:game, room_id})

    %{pid: pid, room_id: room_id, logic: logic}
  end

  test "play valid card broadcasts CardsPlayed and NextTurn", %{pid: pid, logic: logic} do
    player_id = Logic.current_turn(logic)
    card = Logic.next_playable_card(logic, player_id) |> declare_colour()

    assert :ok = Server.play(pid, player_id, [card])

    assert_receive %Events.CardsPlayed{player_id: ^player_id, played_cards: [^card]}
    assert_receive %Events.NextTurn{sequence: 1}
  end

  test "CardsPlayed hand does not contain played card", %{pid: pid, logic: logic} do
    player_id = Logic.current_turn(logic)
    card = Logic.next_playable_card(logic, player_id) |> declare_colour()

    assert :ok = Server.play(pid, player_id, [card])

    assert_receive %Events.CardsPlayed{hand: hand}
    refute Map.has_key?(hand, card)
  end

  test "NextTurn advances to the other player", %{pid: pid, logic: logic} do
    player_id = Logic.current_turn(logic)
    card = Logic.next_playable_card(logic, player_id) |> declare_colour()

    assert :ok = Server.play(pid, player_id, [card])

    assert_receive %Events.NextTurn{player_id: next_player_id}
    assert next_player_id != player_id
  end

  test "play with wrong player returns not_your_turn", %{pid: pid, logic: logic} do
    player_id = Logic.current_turn(logic)
    card = Logic.next_playable_card(logic, player_id) |> declare_colour()

    assert {:error, :not_your_turn} = Server.play(pid, "wrong-player", [card])
  end

  test "second play uses updated turn", %{pid: pid, logic: logic} do
    p1 = Logic.current_turn(logic)
    card1 = logic |> Logic.next_playable_card(p1) |> declare_colour()
    assert :ok = Server.play(pid, p1, [card1])

    assert_receive %Events.CardsPlayed{}
    assert_receive %Events.NextTurn{player_id: p2}

    updated_logic = :sys.get_state(pid).logic_state
    card2 = updated_logic |> Logic.next_playable_card(p2) |> declare_colour()
    assert :ok = Server.play(pid, p2, [card2])

    assert_receive %Events.CardsPlayed{player_id: ^p2}
    assert_receive %Events.NextTurn{sequence: 2}
  end

  defp declare_colour(:wild), do: {:wild, :red}
  defp declare_colour(:wild_draw_4), do: {:wild_draw_4, :red}
  defp declare_colour(card), do: card
end
