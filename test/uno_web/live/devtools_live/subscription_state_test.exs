defmodule UnoWeb.DevtoolsLive.SubscriptionStateTest do
  use UnoWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Uno.Events
  alias Uno.PubSub
  alias UnoWeb.DevtoolsLiveHelpers, as: Helpers

  test "initial mount disables all publish buttons and hides the publish form", %{conn: conn} do
    {:ok, view, _html} = Helpers.mount_devtools(conn)

    for type <-
          ~w(player_joined player_left game_started game_ended sync next_turn cards_played cards_drawn) do
      Helpers.assert_button_disabled(view, type)
    end

    refute has_element?(view, "form[phx-submit='publish-submit']")
    assert Helpers.row_count(view) == 0
  end

  test "subscription toggles enable the matching event groups", %{conn: conn} do
    {:ok, view, _html} = Helpers.mount_devtools(conn)

    Helpers.change_subscription(view, id: "room1", room: true, game: false)

    for type <- ~w(player_joined player_left game_started game_ended) do
      Helpers.assert_button_enabled(view, type)
    end

    for type <- ~w(sync next_turn cards_played cards_drawn) do
      Helpers.assert_button_disabled(view, type)
    end

    Helpers.change_subscription(view, id: "game1", room: false, game: true)

    for type <- ~w(player_joined player_left game_started game_ended) do
      Helpers.assert_button_disabled(view, type)
    end

    for type <- ~w(sync next_turn cards_played cards_drawn) do
      Helpers.assert_button_enabled(view, type)
    end

    Helpers.change_subscription(view, id: "both1", room: true, game: true)

    for type <-
          ~w(player_joined player_left game_started game_ended sync next_turn cards_played cards_drawn) do
      Helpers.assert_button_enabled(view, type)
    end
  end

  test "successful subscription changes reset the publish form and clear streamed events", %{
    conn: conn
  } do
    {:ok, view, _html} = Helpers.mount_devtools(conn)

    Helpers.change_subscription(view, id: "room1", room: true, game: false)
    Helpers.select_event(view, "player_joined")
    assert has_element?(view, Helpers.field_selector("player_joined[player_id]"))

    :ok = PubSub.broadcast({:room, "room1"}, %Events.PlayerJoined{player_id: "p1", name: "Alice"})
    assert Helpers.row_count(view) == 1

    Helpers.change_subscription(view, id: "game1", room: false, game: true)

    refute has_element?(view, "form[phx-submit='publish-submit']")
    assert Helpers.row_count(view) == 0
  end

  test "changing subscriptions moves the liveview to the new topics", %{conn: conn} do
    {:ok, view, _html} = Helpers.mount_devtools(conn)

    Helpers.change_subscription(view, id: "alpha", room: true, game: false)
    :ok = PubSub.broadcast({:room, "alpha"}, %Events.PlayerJoined{player_id: "p1", name: "Alice"})
    assert Helpers.row_count(view) == 1

    Helpers.change_subscription(view, id: "beta", room: true, game: false)
    assert Helpers.row_count(view) == 0

    :ok = PubSub.broadcast({:room, "alpha"}, %Events.PlayerJoined{player_id: "p2", name: "Bob"})
    assert Helpers.row_count(view) == 0

    :ok = PubSub.broadcast({:room, "beta"}, %Events.PlayerJoined{player_id: "p3", name: "Cara"})
    assert Helpers.row_count(view) == 1
  end

  test "invalid subscription edits do not change the active subscription driven state", %{
    conn: conn
  } do
    {:ok, view, _html} = Helpers.mount_devtools(conn)

    Helpers.change_subscription(view, id: "game1", room: false, game: true)
    Helpers.select_event(view, "next_turn")
    assert has_element?(view, Helpers.field_selector("next_turn[player_id]"))

    view
    |> form(
      "form[phx-change='subscribe-change']",
      subscription: %{"id" => "bad-id!", "room" => "false", "game" => "false"}
    )
    |> render_change()

    Helpers.assert_button_enabled(view, "next_turn")
    refute has_element?(view, "#{Helpers.event_button_selector("next_turn")}[disabled]")
    assert has_element?(view, Helpers.field_selector("next_turn[player_id]"))
  end
end
