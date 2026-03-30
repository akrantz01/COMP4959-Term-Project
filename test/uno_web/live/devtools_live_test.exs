defmodule UnoWeb.DevtoolsLiveTest do
  use UnoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Uno.PubSub

  describe "mount" do
    test "renders subscription and publish sections", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/dev/tools")

      assert html =~ "Subscription"
      assert html =~ "Publish Event"
      assert html =~ "Select an event..."
    end
  end

  describe "event type selection" do
    test "selecting an event type shows its fields", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dev/tools")

      html = select_event(view, "player_joined")

      assert html =~ "Player ID"
      assert html =~ "Name"
    end

    test "selecting next_turn shows card and direction fields", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dev/tools")

      html = select_event(view, "next_turn")

      assert html =~ "Sequence"
      assert html =~ "Top Card Colour"
      assert html =~ "Top Card Type"
      assert html =~ "Direction"
    end

    test "clearing event type hides fields", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dev/tools")

      select_event(view, "player_joined")
      html = select_event(view, "")

      refute html =~ "Player ID"
    end
  end

  describe "publishing simple events" do
    test "publishes PlayerJoined to the room topic", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dev/tools")

      subscribe_to_room(view, "testroom")
      PubSub.subscribe({:room, "testroom"})
      select_event(view, "player_joined")

      submit_publish(view, %{player_id: "p1", name: "Alice"})

      assert_receive %Uno.Events.PlayerJoined{player_id: "p1", name: "Alice"}
    end

    test "publishes PlayerLeft to the room topic", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dev/tools")

      subscribe_to_room(view, "testroom")
      PubSub.subscribe({:room, "testroom"})
      select_event(view, "player_left")

      submit_publish(view, %{player_id: "p1"})

      assert_receive %Uno.Events.PlayerLeft{player_id: "p1"}
    end

    test "publishes GameStarted to the room topic", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dev/tools")

      subscribe_to_room(view, "testroom")
      PubSub.subscribe({:room, "testroom"})
      select_event(view, "game_started")

      submit_publish(view, %{room_id: "testroom"})

      assert_receive %Uno.Events.GameStarted{room_id: "testroom"}
    end

    test "publishes GameEnded to the room topic", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dev/tools")

      subscribe_to_room(view, "testroom")
      PubSub.subscribe({:room, "testroom"})
      select_event(view, "game_ended")

      submit_publish(view, %{winner_id: "p1"})

      assert_receive %Uno.Events.GameEnded{winner_id: "p1"}
    end
  end

  describe "publishing NextTurn" do
    test "publishes NextTurn with a normal card", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dev/tools")

      subscribe_to_game(view, "testgame")
      PubSub.subscribe({:game, "testgame"})
      select_event(view, "next_turn")

      submit_publish(view, %{
        sequence: "1",
        player_id: "p1",
        top_card_colour: "red",
        top_card_type: "5",
        direction: "ltr",
        vulnerable_player_id: "",
        skipped: "false",
        chain_enabled: "false"
      })

      assert_receive %Uno.Events.NextTurn{
        sequence: 1,
        player_id: "p1",
        top_card: {:red, 5},
        direction: :ltr,
        vulnerable_player_id: nil,
        skipped: false,
        chain: nil
      }
    end

    test "publishes NextTurn with a wild card and chain", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dev/tools")

      subscribe_to_game(view, "testgame")
      PubSub.subscribe({:game, "testgame"})
      select_event(view, "next_turn")

      # First enable chain via phx-change (without chain fields — they aren't rendered yet)
      view
      |> form("form[phx-change=publish-change]", %{
        publish: %{
          sequence: "3",
          player_id: "p2",
          top_card_colour: "blue",
          top_card_type: "wild_draw_4",
          direction: "rtl",
          vulnerable_player_id: "p1",
          skipped: "false",
          chain_enabled: "true"
        }
      })
      |> render_change()

      # Now submit with all fields including the now-visible chain fields
      submit_publish(view, %{
        sequence: "3",
        player_id: "p2",
        top_card_colour: "blue",
        top_card_type: "wild_draw_4",
        direction: "rtl",
        vulnerable_player_id: "p1",
        skipped: "false",
        chain_enabled: "true",
        chain_type: "wild_draw_4",
        chain_amount: "8"
      })

      assert_receive %Uno.Events.NextTurn{
        sequence: 3,
        player_id: "p2",
        top_card: {:wild_draw_4, :blue},
        direction: :rtl,
        vulnerable_player_id: "p1",
        skipped: false,
        chain: %{type: :wild_draw_4, amount: 8}
      }
    end
  end

  describe "card builder" do
    test "adds and removes cards for CardsPlayed", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dev/tools")

      subscribe_to_game(view, "testgame")
      select_event(view, "cards_played")

      # Add a card via the card builder form
      html = add_card(view, "red", "skip")

      # Card should appear as a badge
      assert html =~ "red skip"

      # Add another card
      html = add_card(view, "blue", "3")

      assert html =~ "blue 3"

      # Remove first card
      html =
        view
        |> element(~s(button[phx-click="remove-card"][phx-value-index="0"]))
        |> render_click()

      refute html =~ "red skip"
      assert html =~ "blue 3"
    end

    test "publishes CardsPlayed with card list", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dev/tools")

      subscribe_to_game(view, "testgame")
      PubSub.subscribe({:game, "testgame"})
      select_event(view, "cards_played")

      add_card(view, "red", "skip")
      submit_publish(view, %{player_id: "p1"})

      assert_receive %Uno.Events.CardsPlayed{
        player_id: "p1",
        played_cards: [{:red, :skip}],
        hand: %{}
      }
    end

    test "publishes CardsPlayed with wild card and colour", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dev/tools")

      subscribe_to_game(view, "testgame")
      PubSub.subscribe({:game, "testgame"})
      select_event(view, "cards_played")

      add_card(view, "blue", "wild_draw_4")
      submit_publish(view, %{player_id: "p1"})

      assert_receive %Uno.Events.CardsPlayed{
        player_id: "p1",
        played_cards: [{:wild_draw_4, :blue}],
        hand: %{}
      }
    end

    test "publishes CardsDrawn with wild cards stripped of colour", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dev/tools")

      subscribe_to_game(view, "testgame")
      PubSub.subscribe({:game, "testgame"})
      select_event(view, "cards_drawn")

      add_card(view, "red", "wild")
      submit_publish(view, %{player_id: "p1"})

      assert_receive %Uno.Events.CardsDrawn{
        player_id: "p1",
        drawn_cards: [:wild],
        hand: %{}
      }
    end

    test "clicking add card with nothing selected does not crash and adds no card",
         %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dev/tools")

      select_event(view, "cards_played")

      html =
        view
        |> element(~s(button[phx-click="add-card"]))
        |> render_click()

      assert html =~ "No cards added yet"
    end

    test "clicking add hand entry with nothing selected does not crash and adds no entry",
         %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dev/tools")

      select_event(view, "cards_played")

      html =
        view
        |> element(~s(button[phx-click="add-hand-entry"]))
        |> render_click()

      assert html =~ "No hand cards added"
    end

    test "shows card builder validation errors after interacting with fields",
         %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dev/tools")

      select_event(view, "cards_played")

      # Touch the fields first so used_input? returns true
      view
      |> form("form[phx-submit=publish-submit]", %{card_builder: %{colour: "", type: ""}})
      |> render_change()

      html =
        view
        |> element(~s(button[phx-click="add-card"]))
        |> render_click()

      assert html =~ "can" and html =~ "be blank"
    end

    test "shows hand entry builder validation errors after interacting with fields",
         %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dev/tools")

      select_event(view, "cards_played")

      view
      |> form("form[phx-submit=publish-submit]", %{
        hand_entry_builder: %{colour: "", type: "", count: ""}
      })
      |> render_change()

      html =
        view
        |> element(~s(button[phx-click="add-hand-entry"]))
        |> render_click()

      assert html =~ "can" and html =~ "be blank"
    end

    test "rejects publishing cards_played with no cards", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dev/tools")

      subscribe_to_game(view, "testgame")
      PubSub.subscribe({:game, "testgame"})
      select_event(view, "cards_played")

      submit_publish(view, %{player_id: "p1"})

      refute_receive %Uno.Events.CardsPlayed{}
    end
  end

  describe "hand builder" do
    test "selecting cards_played shows hand builder", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dev/tools")

      html = select_event(view, "cards_played")

      assert html =~ "Hand"
    end

    test "selecting player_joined does not show hand builder", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dev/tools")

      html = select_event(view, "player_joined")

      refute html =~ "No hand cards added"
    end

    test "adds and removes hand entries for CardsPlayed", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dev/tools")

      subscribe_to_game(view, "testgame")
      select_event(view, "cards_played")

      html = add_hand_entry(view, "red", "skip", 2)
      assert html =~ "red skip"
      assert html =~ "×2"

      html = add_hand_entry(view, "blue", "3", 1)
      assert html =~ "blue 3"

      # Remove first entry
      html =
        view
        |> element(~s(button[phx-click="remove-hand-entry"][phx-value-index="0"]))
        |> render_click()

      refute html =~ "red skip"
      assert html =~ "blue 3"
    end

    test "publishes CardsPlayed with hand entries", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dev/tools")

      subscribe_to_game(view, "testgame")
      PubSub.subscribe({:game, "testgame"})
      select_event(view, "cards_played")

      add_card(view, "red", "skip")
      add_hand_entry(view, "blue", "3", 2)
      add_hand_entry(view, "yellow", "7", 1)
      submit_publish(view, %{player_id: "p1"})

      assert_receive %Uno.Events.CardsPlayed{
        player_id: "p1",
        played_cards: [{:red, :skip}],
        hand: %{{:blue, 3} => 2, {:yellow, 7} => 1}
      }
    end

    test "publishes CardsDrawn with hand entries", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dev/tools")

      subscribe_to_game(view, "testgame")
      PubSub.subscribe({:game, "testgame"})
      select_event(view, "cards_drawn")

      add_card(view, "green", "5")
      add_hand_entry(view, "green", "5", 3)
      submit_publish(view, %{player_id: "p1"})

      assert_receive %Uno.Events.CardsDrawn{
        player_id: "p1",
        drawn_cards: [{:green, 5}],
        hand: %{{:green, 5} => 3}
      }
    end

    test "hand entries support wild cards without colour", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dev/tools")

      subscribe_to_game(view, "testgame")
      PubSub.subscribe({:game, "testgame"})
      select_event(view, "cards_played")

      add_card(view, "red", "5")
      add_hand_entry(view, "", "wild", 2)
      add_hand_entry(view, "", "wild_draw_4", 1)
      add_hand_entry(view, "blue", "3", 3)
      submit_publish(view, %{player_id: "p1"})

      assert_receive %Uno.Events.CardsPlayed{
        player_id: "p1",
        played_cards: [{:red, 5}],
        hand: %{{:blue, 3} => 3, wild: 2, wild_draw_4: 1}
      }
    end

    test "wild hand entries strip colour even if provided", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dev/tools")

      subscribe_to_game(view, "testgame")
      PubSub.subscribe({:game, "testgame"})
      select_event(view, "cards_played")

      add_card(view, "red", "5")
      add_hand_entry(view, "red", "wild", 1)
      submit_publish(view, %{player_id: "p1"})

      assert_receive %Uno.Events.CardsPlayed{
        player_id: "p1",
        played_cards: [{:red, 5}],
        hand: %{wild: 1}
      }
    end
  end

  describe "validation" do
    test "does not publish when no subscription is active", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dev/tools")

      PubSub.subscribe({:room, ""})
      select_event(view, "player_joined")

      submit_publish(view, %{player_id: "p1", name: "Alice"})

      refute_receive %Uno.Events.PlayerJoined{}
    end

    test "does not publish when topic is not subscribed", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dev/tools")

      subscribe_to_room(view, "testroom")
      PubSub.subscribe({:game, "testroom"})
      select_event(view, "next_turn")

      submit_publish(view, %{
        sequence: "1",
        player_id: "p1",
        top_card_colour: "red",
        top_card_type: "5",
        direction: "ltr",
        vulnerable_player_id: "",
        skipped: "false",
        chain_enabled: "false"
      })

      refute_receive %Uno.Events.NextTurn{}
    end

    test "shows form errors for missing required fields", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dev/tools")

      subscribe_to_room(view, "testroom")
      select_event(view, "player_joined")

      html = submit_publish(view, %{player_id: "", name: ""})

      assert html =~ "can" and html =~ "be blank"
    end
  end

  # --- Helpers ---

  defp subscribe_to_room(view, id) do
    view
    |> form("form[phx-change=subscribe-change]", %{
      subscription: %{id: id, room: "true", game: "false"}
    })
    |> render_change()
  end

  defp subscribe_to_game(view, id) do
    view
    |> form("form[phx-change=subscribe-change]", %{
      subscription: %{id: id, room: "false", game: "true"}
    })
    |> render_change()
  end

  defp select_event(view, event_type) do
    view
    |> form("form[phx-change=publish-select-event]", %{event_selector: %{event_type: event_type}})
    |> render_change()
  end

  defp submit_publish(view, params) do
    view
    |> form("form[phx-submit=publish-submit]", %{publish: params})
    |> render_submit()
  end

  defp add_hand_entry(view, colour, type, count) do
    view
    |> form("form[phx-submit=publish-submit]", %{
      hand_entry_builder: %{colour: colour, type: type, count: count}
    })
    |> render_change()

    view
    |> element(~s(button[phx-click="add-hand-entry"]))
    |> render_click()
  end

  defp add_card(view, colour, type) do
    # Update card builder fields via the publish form's phx-change
    view
    |> form("form[phx-submit=publish-submit]", %{card_builder: %{colour: colour, type: type}})
    |> render_change()

    # Click the Add button to add the card
    view
    |> element(~s(button[phx-click="add-card"]))
    |> render_click()
  end
end
