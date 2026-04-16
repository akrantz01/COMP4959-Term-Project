defmodule UnoWeb.Forms.Event.FromEventTest do
  use ExUnit.Case, async: true

  alias Uno.Events
  alias UnoWeb.Forms.Event

  # Round-trip helper: params -> changeset -> to_event -> from_event -> changeset -> to_event
  # The two resulting event structs must be equal.
  defp round_trip(type, params) do
    {:ok, mod} = Event.form(type)
    {:ok, validated} = mod.changeset(mod.new(), params) |> Ecto.Changeset.apply_action(:insert)
    event = mod.to_event(validated)
    recovered_params = mod.from_event(event)

    {:ok, validated2} =
      mod.changeset(mod.new(), recovered_params) |> Ecto.Changeset.apply_action(:insert)

    mod.to_event(validated2)
  end

  describe "PlayerJoined" do
    test "round-trips" do
      params = %{"player_id" => "p1", "name" => "Alice"}

      assert round_trip("player_joined", params) == %Events.PlayerJoined{
               player_id: "p1",
               name: "Alice"
             }
    end

    test "from_event produces correct params" do
      assert UnoWeb.Forms.Event.PlayerJoined.from_event(%Events.PlayerJoined{
               player_id: "p1",
               name: "Alice"
             }) ==
               %{"player_id" => "p1", "name" => "Alice"}
    end
  end

  describe "PlayerLeft" do
    test "round-trips" do
      params = %{"player_id" => "p2"}
      assert round_trip("player_left", params) == %Events.PlayerLeft{player_id: "p2"}
    end
  end

  describe "GameStarted" do
    test "round-trips" do
      params = %{"game_id" => "g1"}
      assert round_trip("game_started", params) == %Events.GameStarted{game_id: "g1"}
    end
  end

  describe "GameEnded" do
    test "round-trips" do
      params = %{"winner_id" => "p1"}
      assert round_trip("game_ended", params) == %Events.GameEnded{winner_id: "p1"}
    end
  end

  describe "NextTurn" do
    test "round-trips without chain" do
      params = %{
        "sequence" => 3,
        "player_id" => "p2",
        "direction" => "rtl",
        "vulnerable_player_id" => "p3",
        "skipped" => true,
        "has_chain" => false,
        "top_card" => %{"type" => "skip", "colour" => "yellow"}
      }

      expected = %Events.NextTurn{
        sequence: 3,
        player_id: "p2",
        direction: :rtl,
        vulnerable_player_id: "p3",
        skipped: true,
        top_card: {:yellow, :skip},
        chain: nil
      }

      assert round_trip("next_turn", params) == expected
    end

    test "round-trips with chain" do
      params = %{
        "sequence" => 4,
        "player_id" => "p3",
        "direction" => "ltr",
        "vulnerable_player_id" => "p1",
        "skipped" => false,
        "has_chain" => true,
        "top_card" => %{"type" => "draw_2", "colour" => "red"},
        "chain" => %{"type" => "draw_2", "amount" => 4}
      }

      expected = %Events.NextTurn{
        sequence: 4,
        player_id: "p3",
        direction: :ltr,
        vulnerable_player_id: "p1",
        skipped: false,
        top_card: {:red, :draw_2},
        chain: %{type: :draw_2, amount: 4}
      }

      assert round_trip("next_turn", params) == expected
    end

    test "round-trips with wild top card" do
      params = %{
        "sequence" => 5,
        "player_id" => "p1",
        "direction" => "ltr",
        "has_chain" => false,
        "top_card" => %{"type" => "wild", "colour" => "blue"}
      }

      expected = %Events.NextTurn{
        sequence: 5,
        player_id: "p1",
        direction: :ltr,
        top_card: {:wild, :blue},
        chain: nil
      }

      assert round_trip("next_turn", params) == expected
    end
  end

  describe "Sync" do
    test "round-trips with single player, no chain" do
      params = %{
        "sequence" => 1,
        "direction" => "ltr",
        "vulnerable_player_id" => "p2",
        "has_chain" => false,
        "top_card" => %{"type" => "5", "colour" => "red"},
        "players" => [%{"id" => "p1", "name" => "Alice"}],
        "hands" => [
          %{
            "player_id" => "p1",
            "cards" => [%{"type" => "7", "colour" => "blue", "count" => 1}]
          }
        ]
      }

      expected = %Events.Sync{
        sequence: 1,
        direction: :ltr,
        vulnerable_player_id: "p2",
        top_card: {:red, 5},
        chain: nil,
        players: [{"p1", "Alice"}],
        hands: %{"p1" => %{{:blue, 7} => 1}}
      }

      assert round_trip("sync", params) == expected
    end

    test "round-trips with multiple players and chain" do
      params = %{
        "sequence" => 2,
        "direction" => "rtl",
        "vulnerable_player_id" => "p2",
        "has_chain" => true,
        "top_card" => %{"type" => "reverse", "colour" => "green"},
        "chain" => %{"type" => "wild_draw_4", "amount" => 8},
        "players" => [
          %{"id" => "p1", "name" => "Alice"},
          %{"id" => "p2", "name" => "Bob"}
        ],
        "hands" => [
          %{
            "player_id" => "p1",
            "cards" => [
              %{"type" => "3", "colour" => "yellow", "count" => 2},
              %{"type" => "wild", "count" => 1}
            ]
          },
          %{
            "player_id" => "p2",
            "cards" => [%{"type" => "9", "colour" => "red", "count" => 1}]
          }
        ]
      }

      expected = %Events.Sync{
        sequence: 2,
        direction: :rtl,
        vulnerable_player_id: "p2",
        top_card: {:green, :reverse},
        chain: %{type: :wild_draw_4, amount: 8},
        players: [{"p1", "Alice"}, {"p2", "Bob"}],
        hands: %{
          "p1" => %{{:yellow, 3} => 2, :wild => 1},
          "p2" => %{{:red, 9} => 1}
        }
      }

      assert round_trip("sync", params) == expected
    end
  end

  describe "CardsPlayed" do
    test "round-trips single card" do
      params = %{
        "player_id" => "p1",
        "played_cards" => [%{"type" => "4", "colour" => "blue"}],
        "hand" => [%{"type" => "7", "colour" => "green", "count" => 2}]
      }

      expected = %Events.CardsPlayed{
        player_id: "p1",
        played_cards: [{:blue, 4}],
        hand: %{{:green, 7} => 2}
      }

      assert round_trip("cards_played", params) == expected
    end

    test "round-trips wild card" do
      params = %{
        "player_id" => "p2",
        "played_cards" => [%{"type" => "wild_draw_4", "colour" => "red"}],
        "hand" => [%{"type" => "wild", "count" => 1}]
      }

      expected = %Events.CardsPlayed{
        player_id: "p2",
        played_cards: [{:wild_draw_4, :red}],
        hand: %{:wild => 1}
      }

      assert round_trip("cards_played", params) == expected
    end
  end

  describe "CardsDrawn" do
    test "round-trips single drawn card" do
      params = %{
        "player_id" => "p1",
        "drawn_cards" => [%{"type" => "5", "colour" => "red"}],
        "hand" => [%{"type" => "8", "colour" => "yellow", "count" => 1}]
      }

      expected = %Events.CardsDrawn{
        player_id: "p1",
        drawn_cards: [{:red, 5}],
        hand: %{{:yellow, 8} => 1}
      }

      assert round_trip("cards_drawn", params) == expected
    end

    test "round-trips wild drawn card" do
      params = %{
        "player_id" => "p3",
        "drawn_cards" => [%{"type" => "wild"}],
        "hand" => [%{"type" => "wild", "count" => 1}]
      }

      expected = %Events.CardsDrawn{
        player_id: "p3",
        drawn_cards: [:wild],
        hand: %{:wild => 1}
      }

      assert round_trip("cards_drawn", params) == expected
    end
  end
end
