defmodule UnoWeb.DevtoolsLive.GamePublishTest do
  use UnoWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Uno.Events
  alias UnoWeb.DevtoolsLiveHelpers, as: Helpers

  setup %{conn: conn} do
    {:ok, view, _html} = Helpers.mount_devtools(conn)
    Helpers.change_subscription(view, id: "game1", room: false, game: true)
    Helpers.subscribe_topic(:game, "game1")
    %{view: view}
  end

  test "publishes sync events with and without chain", %{view: view} do
    Helpers.select_event(view, "sync")
    Helpers.publish_submit(view, Helpers.sync_payload(:single_without_chain))

    assert_receive %Events.Sync{
      sequence: 1,
      current_player_id: "p1",
      top_card: {:red, 5},
      direction: :ltr,
      players: [{"p1", "Alice"}],
      hands: %{"p1" => %{{:blue, 7} => 1}},
      vulnerable_player_id: "p2",
      chain: nil
    }

    assert render(view) =~ "Published Sync event!"
    refute has_element?(view, "form[phx-submit='publish-submit']")
    assert Helpers.row_count(view) == 1
    assert render(view) =~ "Sync"

    Helpers.select_event(view, "sync")
    Helpers.publish_submit(view, Helpers.sync_payload(:multi_with_chain))

    assert_receive %Events.Sync{
      sequence: 2,
      current_player_id: "p1",
      top_card: {:green, :reverse},
      direction: :rtl,
      players: [{"p1", "Alice"}, {"p2", "Bob"}],
      hands: %{
        "p1" => %{{:yellow, 3} => 2, :wild => 1},
        "p2" => %{{:red, 9} => 1}
      },
      vulnerable_player_id: "p2",
      chain: %{type: :wild_draw_4, amount: 8}
    }

    assert render(view) =~ "Published Sync event!"
    refute has_element?(view, "form[phx-submit='publish-submit']")
    assert Helpers.row_count(view) == 2
  end

  test "publishes next turn events with and without chain", %{view: view} do
    Helpers.select_event(view, "next_turn")
    Helpers.publish_submit(view, Helpers.next_turn_payload(:without_chain))

    assert_receive %Events.NextTurn{
      sequence: 3,
      player_id: "p2",
      top_card: {:yellow, :skip},
      direction: :rtl,
      vulnerable_player_id: "p3",
      skipped: true,
      chain: nil
    }

    assert render(view) =~ "Published Next Turn event!"
    refute has_element?(view, "form[phx-submit='publish-submit']")
    assert Helpers.row_count(view) == 1
    assert render(view) =~ "Game"

    Helpers.select_event(view, "next_turn")
    Helpers.publish_submit(view, Helpers.next_turn_payload(:with_chain))

    assert_receive %Events.NextTurn{
      sequence: 4,
      player_id: "p3",
      top_card: {:red, :draw_2},
      direction: :ltr,
      vulnerable_player_id: "p1",
      skipped: false,
      chain: %{type: :draw_2, amount: 4}
    }

    assert render(view) =~ "Published Next Turn event!"
    refute has_element?(view, "form[phx-submit='publish-submit']")
    assert Helpers.row_count(view) == 2
  end

  test "publishes cards played events for single and multiple entries", %{view: view} do
    Helpers.select_event(view, "cards_played")
    Helpers.publish_submit(view, Helpers.cards_played_payload(:single))

    assert_receive %Events.CardsPlayed{
      player_id: "p1",
      played_cards: [{:blue, 4}],
      hand: %{{:green, 7} => 2}
    }

    assert render(view) =~ "Published Cards Played event!"
    refute has_element?(view, "form[phx-submit='publish-submit']")
    assert Helpers.row_count(view) == 1
    assert render(view) =~ "Game"

    Helpers.select_event(view, "cards_played")
    Helpers.publish_submit(view, Helpers.cards_played_payload(:multi))

    assert_receive %Events.CardsPlayed{
      player_id: "p2",
      played_cards: [{:yellow, :reverse}, {:wild_draw_4, :red}],
      hand: %{{:blue, 1} => 1, {:green, :skip} => 3}
    }

    assert render(view) =~ "Published Cards Played event!"
    refute has_element?(view, "form[phx-submit='publish-submit']")
    assert Helpers.row_count(view) == 2
  end

  test "publishes cards drawn events for single and multiple entries", %{view: view} do
    Helpers.select_event(view, "cards_drawn")
    Helpers.publish_submit(view, Helpers.cards_drawn_payload(:single))

    assert_receive %Events.CardsDrawn{
      player_id: "p1",
      drawn_cards: [{:red, 5}],
      hand: %{{:yellow, 8} => 1}
    }

    assert render(view) =~ "Published Cards Drawn event!"
    refute has_element?(view, "form[phx-submit='publish-submit']")
    assert Helpers.row_count(view) == 1
    assert render(view) =~ "Game"

    Helpers.select_event(view, "cards_drawn")
    Helpers.publish_submit(view, Helpers.cards_drawn_payload(:multi))

    assert_receive %Events.CardsDrawn{
      player_id: "p3",
      drawn_cards: [{:blue, :reverse}, :wild],
      hand: %{{:green, 2} => 2, :wild => 1}
    }

    assert render(view) =~ "Published Cards Drawn event!"
    refute has_element?(view, "form[phx-submit='publish-submit']")
    assert Helpers.row_count(view) == 2
  end
end
