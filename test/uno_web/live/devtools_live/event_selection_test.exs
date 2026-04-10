defmodule UnoWeb.DevtoolsLive.EventSelectionTest do
  use UnoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias UnoWeb.DevtoolsLiveHelpers, as: Helpers

  test "selecting each event type renders only that event's fields", %{conn: conn} do
    {:ok, view, _html} = Helpers.mount_devtools(conn)
    Helpers.change_subscription(view, id: "all1", room: true, game: true)

    cases = [
      {"player_joined", "player_joined[player_id]", "player_joined[name]"},
      {"player_left", "player_left[player_id]", nil},
      {"game_started", "game_started[game_id]", nil},
      {"game_ended", "game_ended[winner_id]", nil},
      {"sync", "sync[sequence]", "sync[players_sort][]"},
      {"next_turn", "next_turn[player_id]", "next_turn[skipped]"},
      {"cards_played", "cards_played[player_id]", "cards_played[played_cards_sort][]"},
      {"cards_drawn", "cards_drawn[player_id]", "cards_drawn[drawn_cards_sort][]"}
    ]

    Enum.reduce(cases, nil, fn {type, required_name, extra_name}, previous_type ->
      Helpers.select_event(view, type)

      assert has_element?(view, Helpers.field_selector(required_name))

      if extra_name do
        assert has_element?(view, Helpers.field_selector(extra_name))
      end

      if previous_type do
        refute has_element?(view, Helpers.field_selector("#{previous_type}[player_id]"))
      end

      type
    end)
  end

  test "switching event types clears in progress nested state", %{conn: conn} do
    {:ok, view, _html} = Helpers.mount_devtools(conn)
    Helpers.change_subscription(view, id: "game1", room: false, game: true)

    Helpers.select_event(view, "sync")

    sync_with_two_players =
      Helpers.sync_payload(:multi_with_chain)

    Helpers.publish_change(view, sync_with_two_players)
    assert Helpers.count_matches(view, ~r/name="sync\[players\]\[\d+\]\[id\]"/) == 2

    Helpers.select_event(view, "cards_played")
    assert has_element?(view, Helpers.field_selector("cards_played[player_id]"))
    refute has_element?(view, Helpers.field_selector("sync[sequence]"))

    Helpers.select_event(view, "sync")
    assert Helpers.count_matches(view, ~r/name="sync\[players\]\[\d+\]\[id\]"/) == 0
    refute has_element?(view, Helpers.field_selector("sync[chain][type]"))
  end

  test "toggling has_chain shows and hides the chain subform for sync and next_turn", %{
    conn: conn
  } do
    {:ok, view, _html} = Helpers.mount_devtools(conn)
    Helpers.change_subscription(view, id: "game1", room: false, game: true)

    Helpers.select_event(view, "sync")
    refute has_element?(view, Helpers.field_selector("sync[chain][type]"))
    refute has_element?(view, Helpers.field_selector("sync[chain][amount]"))

    Helpers.publish_change(view, Helpers.sync_payload(:multi_with_chain))
    assert has_element?(view, Helpers.field_selector("sync[chain][type]"))
    assert has_element?(view, Helpers.field_selector("sync[chain][amount]"))

    Helpers.publish_change(view, Helpers.sync_payload(:single_without_chain))
    refute has_element?(view, Helpers.field_selector("sync[chain][type]"))
    refute has_element?(view, Helpers.field_selector("sync[chain][amount]"))

    Helpers.select_event(view, "next_turn")
    refute has_element?(view, Helpers.field_selector("next_turn[chain][type]"))
    refute has_element?(view, Helpers.field_selector("next_turn[chain][amount]"))

    Helpers.publish_change(view, Helpers.next_turn_payload(:with_chain))
    assert has_element?(view, Helpers.field_selector("next_turn[chain][type]"))
    assert has_element?(view, Helpers.field_selector("next_turn[chain][amount]"))

    Helpers.publish_change(view, Helpers.next_turn_payload(:without_chain))
    refute has_element?(view, Helpers.field_selector("next_turn[chain][type]"))
    refute has_element?(view, Helpers.field_selector("next_turn[chain][amount]"))
  end

  test "sync nested collections can be added and removed through form changes", %{conn: conn} do
    {:ok, view, _html} = Helpers.mount_devtools(conn)
    Helpers.change_subscription(view, id: "game1", room: false, game: true)
    Helpers.select_event(view, "sync")

    one_player_add =
      %{
        "sync" => %{
          "players_sort" => ["new"],
          "players_drop" => [""]
        }
      }

    Helpers.publish_change(view, one_player_add)
    assert Helpers.count_matches(view, ~r/name="sync\[players\]\[\d+\]\[id\]"/) == 1

    two_players_add =
      %{
        "sync" => %{
          "players" => %{"0" => %{"id" => "p1", "name" => "Alice"}},
          "players_sort" => ["0", "new"],
          "players_drop" => [""]
        }
      }

    Helpers.publish_change(view, two_players_add)
    assert Helpers.count_matches(view, ~r/name="sync\[players\]\[\d+\]\[id\]"/) == 2

    remove_second_player =
      %{
        "sync" => %{
          "players" => %{
            "0" => %{"id" => "p1", "name" => "Alice"},
            "1" => %{"id" => "p2", "name" => "Bob"}
          },
          "players_sort" => ["0", "1"],
          "players_drop" => ["", "1"]
        }
      }

    Helpers.publish_change(view, remove_second_player)
    assert Helpers.count_matches(view, ~r/name="sync\[players\]\[\d+\]\[id\]"/) == 1

    Helpers.publish_change(view, Helpers.sync_payload(:single_without_chain))
    assert Helpers.count_matches(view, ~r/name="sync\[hands\]\[\d+\]\[player_id\]"/) == 1

    assert Helpers.count_matches(view, ~r/name="sync\[hands\]\[0\]\[cards\]\[\d+\]\[count\]"/) ==
             1

    Helpers.publish_change(view, Helpers.sync_payload(:multi_with_chain))
    assert Helpers.count_matches(view, ~r/name="sync\[hands\]\[\d+\]\[player_id\]"/) == 2

    assert Helpers.count_matches(view, ~r/name="sync\[hands\]\[0\]\[cards\]\[\d+\]\[count\]"/) ==
             2

    remove_one_hand =
      %{
        "sync" => %{
          "sequence" => "2",
          "direction" => "rtl",
          "vulnerable_player_id" => "p2",
          "has_chain" => "true",
          "top_card" => %{"type" => "reverse", "colour" => "green"},
          "chain" => %{"type" => "wild_draw_4", "amount" => "8"},
          "players" => %{
            "0" => %{"id" => "p1", "name" => "Alice"},
            "1" => %{"id" => "p2", "name" => "Bob"}
          },
          "players_sort" => ["0", "1"],
          "players_drop" => [""],
          "hands" => %{
            "0" => %{
              "player_id" => "p1",
              "cards" => %{
                "0" => %{"type" => "3", "colour" => "yellow", "count" => "2"},
                "1" => %{"type" => "wild", "count" => "1"}
              },
              "cards_sort" => ["0", "1"],
              "cards_drop" => [""]
            },
            "1" => %{
              "player_id" => "p2",
              "cards" => %{
                "0" => %{"type" => "9", "colour" => "red", "count" => "1"}
              },
              "cards_sort" => ["0"],
              "cards_drop" => [""]
            }
          },
          "hands_sort" => ["0", "1"],
          "hands_drop" => ["", "1"]
        }
      }

    Helpers.publish_change(view, remove_one_hand)
    assert Helpers.count_matches(view, ~r/name="sync\[hands\]\[\d+\]\[player_id\]"/) == 1

    remove_one_nested_card =
      %{
        "sync" => %{
          "sequence" => "2",
          "direction" => "rtl",
          "vulnerable_player_id" => "p2",
          "has_chain" => "true",
          "top_card" => %{"type" => "reverse", "colour" => "green"},
          "chain" => %{"type" => "wild_draw_4", "amount" => "8"},
          "players" => %{"0" => %{"id" => "p1", "name" => "Alice"}},
          "players_sort" => ["0"],
          "players_drop" => [""],
          "hands" => %{
            "0" => %{
              "player_id" => "p1",
              "cards" => %{
                "0" => %{"type" => "3", "colour" => "yellow", "count" => "2"},
                "1" => %{"type" => "wild", "count" => "1"}
              },
              "cards_sort" => ["0", "1"],
              "cards_drop" => ["", "1"]
            }
          },
          "hands_sort" => ["0"],
          "hands_drop" => [""]
        }
      }

    Helpers.publish_change(view, remove_one_nested_card)

    assert Helpers.count_matches(view, ~r/name="sync\[hands\]\[0\]\[cards\]\[\d+\]\[count\]"/) ==
             1
  end

  test "cards played and cards drawn nested collections can be added and removed", %{conn: conn} do
    {:ok, view, _html} = Helpers.mount_devtools(conn)
    Helpers.change_subscription(view, id: "game1", room: false, game: true)

    Helpers.select_event(view, "cards_played")
    Helpers.publish_change(view, Helpers.cards_played_payload(:single))

    assert Helpers.count_matches(view, ~r/name="cards_played\[played_cards\]\[\d+\]\[type\]"/) ==
             1

    assert Helpers.count_matches(view, ~r/name="cards_played\[hand\]\[\d+\]\[count\]"/) == 1

    Helpers.publish_change(view, Helpers.cards_played_payload(:multi))

    assert Helpers.count_matches(view, ~r/name="cards_played\[played_cards\]\[\d+\]\[type\]"/) ==
             2

    assert Helpers.count_matches(view, ~r/name="cards_played\[hand\]\[\d+\]\[count\]"/) == 2

    remove_played_and_hand =
      %{
        "cards_played" => %{
          "player_id" => "p2",
          "played_cards" => %{
            "0" => %{"type" => "reverse", "colour" => "yellow"},
            "1" => %{"type" => "wild_draw_4", "colour" => "red"}
          },
          "played_cards_sort" => ["0", "1"],
          "played_cards_drop" => ["", "1"],
          "hand" => %{
            "0" => %{"type" => "1", "colour" => "blue", "count" => "1"},
            "1" => %{"type" => "skip", "colour" => "green", "count" => "3"}
          },
          "hand_sort" => ["0", "1"],
          "hand_drop" => ["", "1"]
        }
      }

    Helpers.publish_change(view, remove_played_and_hand)

    assert Helpers.count_matches(view, ~r/name="cards_played\[played_cards\]\[\d+\]\[type\]"/) ==
             1

    assert Helpers.count_matches(view, ~r/name="cards_played\[hand\]\[\d+\]\[count\]"/) == 1

    Helpers.select_event(view, "cards_drawn")
    Helpers.publish_change(view, Helpers.cards_drawn_payload(:single))
    assert Helpers.count_matches(view, ~r/name="cards_drawn\[drawn_cards\]\[\d+\]\[type\]"/) == 1
    assert Helpers.count_matches(view, ~r/name="cards_drawn\[hand\]\[\d+\]\[count\]"/) == 1

    Helpers.publish_change(view, Helpers.cards_drawn_payload(:multi))
    assert Helpers.count_matches(view, ~r/name="cards_drawn\[drawn_cards\]\[\d+\]\[type\]"/) == 2
    assert Helpers.count_matches(view, ~r/name="cards_drawn\[hand\]\[\d+\]\[count\]"/) == 2

    remove_drawn_and_hand =
      %{
        "cards_drawn" => %{
          "player_id" => "p3",
          "drawn_cards" => %{
            "0" => %{"type" => "reverse", "colour" => "blue"},
            "1" => %{"type" => "wild"}
          },
          "drawn_cards_sort" => ["0", "1"],
          "drawn_cards_drop" => ["", "1"],
          "hand" => %{
            "0" => %{"type" => "2", "colour" => "green", "count" => "2"},
            "1" => %{"type" => "wild", "count" => "1"}
          },
          "hand_sort" => ["0", "1"],
          "hand_drop" => ["", "1"]
        }
      }

    Helpers.publish_change(view, remove_drawn_and_hand)
    assert Helpers.count_matches(view, ~r/name="cards_drawn\[drawn_cards\]\[\d+\]\[type\]"/) == 1
    assert Helpers.count_matches(view, ~r/name="cards_drawn\[hand\]\[\d+\]\[count\]"/) == 1
  end
end
