defmodule UnoWeb.DevtoolsLive.ScenarioTest do
  use UnoWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Uno.Events
  alias UnoWeb.DevtoolsLiveHelpers, as: Helpers

  setup %{conn: conn} do
    {:ok, view, _html} = Helpers.mount_devtools(conn)
    Helpers.change_subscription(view, id: "room1", room: true, game: true)
    Helpers.subscribe_topic(:room, "room1")
    Helpers.subscribe_topic(:game, "room1")
    %{view: view}
  end

  describe "scenario upload — run" do
    test "runs a single-event scenario", %{view: view} do
      json = Jason.encode!(%{"event" => "game_started", "params" => %{"game_id" => "g1"}})

      Helpers.upload_scenario(view, json)

      assert_receive %Events.GameStarted{game_id: "g1"}
      assert render(view) =~ "Scenario complete!"
    end

    test "accepts a single object (not wrapped in array)", %{view: view} do
      json = Jason.encode!(%{"event" => "game_started", "params" => %{"game_id" => "g2"}})

      Helpers.upload_scenario(view, json)

      assert_receive %Events.GameStarted{game_id: "g2"}
    end

    test "runs a multi-event scenario in order", %{view: view} do
      json =
        Jason.encode!([
          %{"delay_ms" => 0, "event" => "game_started", "params" => %{"game_id" => "g1"}},
          %{
            "delay_ms" => 0,
            "event" => "player_joined",
            "params" => %{"player_id" => "p1", "name" => "Alice"}
          }
        ])

      Helpers.upload_scenario(view, json)

      assert_receive %Events.GameStarted{game_id: "g1"}
      assert_receive %Events.PlayerJoined{player_id: "p1", name: "Alice"}
      assert render(view) =~ "Scenario complete!"
    end

    test "forces first event delay_ms to 0 regardless of JSON value", %{view: view} do
      # Even if JSON says 10_000ms for the first event, it should broadcast immediately.
      # We verify this by asserting the event is received rather than timing out.
      json =
        Jason.encode!([
          %{"delay_ms" => 10_000, "event" => "game_started", "params" => %{"game_id" => "g3"}}
        ])

      Helpers.upload_scenario(view, json)

      assert_receive %Events.GameStarted{game_id: "g3"}
    end

    test "shows error and broadcasts nothing when an entry is invalid", %{view: view} do
      # Missing required top_card on next_turn entry
      json =
        Jason.encode!([
          %{"delay_ms" => 0, "event" => "game_started", "params" => %{"game_id" => "g1"}},
          %{
            "delay_ms" => 0,
            "event" => "next_turn",
            "params" => %{"sequence" => 1, "player_id" => "p1", "direction" => "ltr"}
          }
        ])

      Helpers.upload_scenario(view, json)

      refute_receive %Events.GameStarted{}
      assert render(view) =~ "Scenario error"
      assert render(view) =~ "index 1"
    end

    test "shows error for invalid JSON", %{view: view} do
      Helpers.upload_scenario(view, "not valid json {{{")

      assert render(view) =~ "Invalid scenario JSON:"
    end

    test "disables event tab and publish buttons during replay", %{view: view} do
      # Start a long-delayed scenario so replaying stays true for the duration of the test
      json =
        Jason.encode!([
          %{"delay_ms" => 0, "event" => "game_started", "params" => %{"game_id" => "g1"}},
          %{"delay_ms" => 30_000, "event" => "game_ended", "params" => %{"winner_id" => "p1"}}
        ])

      Helpers.upload_scenario(view, json)

      assert_receive %Events.GameStarted{game_id: "g1"}

      html = render(view)

      # Event tab radio is disabled
      assert html =~ ~r/input[^>]*aria-label="Event"[^>]*disabled/
      # All event selection buttons are disabled
      assert has_element?(view, "button[phx-value-type='game_ended'][disabled]")
    end
  end

  describe "scenario download" do
    test "download button is disabled when no events have been received", %{view: view} do
      assert has_element?(view, "button[phx-click='scenario-download'][disabled]")
    end

    test "download button becomes enabled after receiving an event", %{view: view} do
      Helpers.select_event(view, "game_started")
      Helpers.publish_submit(view, %{"game_started" => %{"game_id" => "g1"}})

      assert_receive %Events.GameStarted{}

      # Allow handle_info to process the received event
      _ = render(view)

      refute has_element?(view, "button[phx-click='scenario-download'][disabled]")
    end

    test "scenario_events cleared on subscription change", %{view: view} do
      Helpers.select_event(view, "game_started")
      Helpers.publish_submit(view, %{"game_started" => %{"game_id" => "g1"}})
      assert_receive %Events.GameStarted{}
      _ = render(view)
      refute has_element?(view, "button[phx-click='scenario-download'][disabled]")

      Helpers.change_subscription(view, id: "room2", room: true, game: false)

      assert has_element?(view, "button[phx-click='scenario-download'][disabled]")
    end
  end

  describe "from_event round-trip via scenario download + upload" do
    test "events published via form can be replayed after download", %{view: view} do
      Helpers.select_event(view, "game_started")
      Helpers.publish_submit(view, %{"game_started" => %{"game_id" => "abc"}})
      assert_receive %Events.GameStarted{game_id: "abc"}

      # Trigger download push_event — the LiveView sends it to the client
      view |> element("button[phx-click='scenario-download']") |> render_click()
      assert_push_event(view, "devtools:download", %{filename: filename, content: content})

      assert String.ends_with?(filename, ".json")
      [entry] = Jason.decode!(content)
      assert entry["event"] == "game_started"
      assert entry["delay_ms"] == 0
      assert entry["params"]["game_id"] == "abc"

      # Now re-upload and replay
      Helpers.upload_scenario(view, content)
      assert_receive %Events.GameStarted{game_id: "abc"}
    end
  end
end
