defmodule UnoWeb.DevtoolsLive.RoomPublishTest do
  use UnoWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Uno.Events
  alias UnoWeb.DevtoolsLiveHelpers, as: Helpers

  setup %{conn: conn} do
    {:ok, view, _html} = Helpers.mount_devtools(conn)
    Helpers.change_subscription(view, id: "room1", room: true, game: false)
    Helpers.subscribe_topic(:room, "room1")
    %{view: view}
  end

  test "publishes player joined events", %{view: view} do
    Helpers.select_event(view, "player_joined")

    Helpers.publish_submit(view, %{
      "player_joined" => %{"player_id" => "p1", "name" => "Alice"}
    })

    assert_receive %Events.PlayerJoined{player_id: "p1", name: "Alice"}
    assert render(view) =~ "Published Player Joined event!"
    refute has_element?(view, "form[phx-submit='publish-submit']")
    assert Helpers.row_count(view) == 1
    assert render(view) =~ "Room"
  end

  test "publishes player left events", %{view: view} do
    Helpers.select_event(view, "player_left")

    Helpers.publish_submit(view, %{
      "player_left" => %{"player_id" => "p2"}
    })

    assert_receive %Events.PlayerLeft{player_id: "p2"}
    assert render(view) =~ "Published Player Left event!"
    refute has_element?(view, "form[phx-submit='publish-submit']")
    assert Helpers.row_count(view) == 1
    assert render(view) =~ "Room"
  end

  test "publishes game started events", %{view: view} do
    Helpers.select_event(view, "game_started")

    Helpers.publish_submit(view, %{
      "game_started" => %{"game_id" => "g1"}
    })

    assert_receive %Events.GameStarted{game_id: "g1"}
    assert render(view) =~ "Published Game Started event!"
    refute has_element?(view, "form[phx-submit='publish-submit']")
    assert Helpers.row_count(view) == 1
    assert render(view) =~ "Room"
  end

  test "publishes game ended events", %{view: view} do
    Helpers.select_event(view, "game_ended")

    Helpers.publish_submit(view, %{
      "game_ended" => %{"winner_id" => "p3"}
    })

    assert_receive %Events.GameEnded{winner_id: "p3"}
    assert render(view) =~ "Published Game Ended event!"
    refute has_element?(view, "form[phx-submit='publish-submit']")
    assert Helpers.row_count(view) == 1
    assert render(view) =~ "Room"
  end
end
