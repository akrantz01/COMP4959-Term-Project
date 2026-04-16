defmodule UnoWeb.DevtoolsLiveHelpers do
  @moduledoc false
  @endpoint UnoWeb.Endpoint

  import ExUnit.Assertions
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias Uno.PubSub

  def mount_devtools(conn) do
    live(conn, "/dev/tools")
  end

  def upload_scenario(view, json) do
    upload =
      file_input(view, "form[phx-submit='scenario-run']", :scenario, [
        %{name: "scenario.json", content: json, type: "application/json"}
      ])

    render_upload(upload, "scenario.json")

    view
    |> element("form[phx-submit='scenario-run']")
    |> render_submit()
  end

  def change_subscription(view, attrs) do
    view
    |> form(
      "form[phx-change='subscribe-change']",
      subscription: %{
        id: attrs[:id] || "",
        room: bool_param(attrs[:room] || false),
        game: bool_param(attrs[:game] || false)
      }
    )
    |> render_change()
  end

  def select_event(view, type) do
    view
    |> element(event_button_selector(type))
    |> render_click()
  end

  def publish_change(view, payload) do
    view
    |> element("form[phx-submit='publish-submit']")
    |> render_change(payload)
  end

  def publish_submit(view, payload) do
    view
    |> element("form[phx-submit='publish-submit']")
    |> render_submit(payload)
  end

  def event_button_selector(type), do: ~s(button[phx-value-type="#{type}"])

  def field_selector(name), do: ~s([name="#{name}"])

  def row_count(view) do
    _ = :sys.get_state(view.pid)
    html = render(view)

    case Regex.run(~r/<tbody[^>]*>(.*)<\/tbody>/sU, html, capture: :all_but_first) do
      [tbody] -> Regex.scan(~r/<tr\b/, tbody) |> length()
      _ -> 0
    end
  end

  def count_matches(view, regex) do
    view
    |> render()
    |> then(&Regex.scan(regex, &1))
    |> length()
  end

  def assert_button_disabled(view, type) do
    assert has_element?(view, "#{event_button_selector(type)}[disabled]")
  end

  def assert_button_enabled(view, type) do
    assert has_element?(view, event_button_selector(type))
    refute has_element?(view, "#{event_button_selector(type)}[disabled]")
  end

  def subscribe_topic(kind, id) do
    :ok = PubSub.subscribe({kind, id})
  end

  def next_turn_payload(:without_chain) do
    %{
      "next_turn" => %{
        "sequence" => "3",
        "player_id" => "p2",
        "direction" => "rtl",
        "vulnerable_player_id" => "p3",
        "skipped" => "true",
        "has_chain" => "false",
        "top_card" => %{"type" => "skip", "colour" => "yellow"}
      }
    }
  end

  def next_turn_payload(:with_chain) do
    %{
      "next_turn" => %{
        "sequence" => "4",
        "player_id" => "p3",
        "direction" => "ltr",
        "vulnerable_player_id" => "p1",
        "skipped" => "false",
        "has_chain" => "true",
        "top_card" => %{"type" => "draw_2", "colour" => "red"},
        "chain" => %{"type" => "draw_2", "amount" => "4"}
      }
    }
  end

  def sync_payload(:single_without_chain) do
    %{
      "sync" => %{
        "sequence" => "1",
        "direction" => "ltr",
        "vulnerable_player_id" => "p2",
        "has_chain" => "false",
        "top_card" => %{"type" => "5", "colour" => "red"},
        "players" => %{
          "0" => %{"id" => "p1", "name" => "Alice"}
        },
        "players_sort" => ["0"],
        "players_drop" => [""],
        "hands" => %{
          "0" => %{
            "player_id" => "p1",
            "cards" => %{
              "0" => %{"type" => "7", "colour" => "blue", "count" => "1"}
            },
            "cards_sort" => ["0"],
            "cards_drop" => [""]
          }
        },
        "hands_sort" => ["0"],
        "hands_drop" => [""]
      }
    }
  end

  def sync_payload(:multi_with_chain) do
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
        "hands_drop" => [""]
      }
    }
  end

  def cards_played_payload(:single) do
    %{
      "cards_played" => %{
        "player_id" => "p1",
        "played_cards" => %{
          "0" => %{"type" => "4", "colour" => "blue"}
        },
        "played_cards_sort" => ["0"],
        "played_cards_drop" => [""],
        "hand" => %{
          "0" => %{"type" => "7", "colour" => "green", "count" => "2"}
        },
        "hand_sort" => ["0"],
        "hand_drop" => [""]
      }
    }
  end

  def cards_played_payload(:multi) do
    %{
      "cards_played" => %{
        "player_id" => "p2",
        "played_cards" => %{
          "0" => %{"type" => "reverse", "colour" => "yellow"},
          "1" => %{"type" => "wild_draw_4", "colour" => "red"}
        },
        "played_cards_sort" => ["0", "1"],
        "played_cards_drop" => [""],
        "hand" => %{
          "0" => %{"type" => "1", "colour" => "blue", "count" => "1"},
          "1" => %{"type" => "skip", "colour" => "green", "count" => "3"}
        },
        "hand_sort" => ["0", "1"],
        "hand_drop" => [""]
      }
    }
  end

  def cards_drawn_payload(:single) do
    %{
      "cards_drawn" => %{
        "player_id" => "p1",
        "drawn_cards" => %{
          "0" => %{"type" => "5", "colour" => "red"}
        },
        "drawn_cards_sort" => ["0"],
        "drawn_cards_drop" => [""],
        "hand" => %{
          "0" => %{"type" => "8", "colour" => "yellow", "count" => "1"}
        },
        "hand_sort" => ["0"],
        "hand_drop" => [""]
      }
    }
  end

  def cards_drawn_payload(:multi) do
    %{
      "cards_drawn" => %{
        "player_id" => "p3",
        "drawn_cards" => %{
          "0" => %{"type" => "reverse", "colour" => "blue"},
          "1" => %{"type" => "wild"}
        },
        "drawn_cards_sort" => ["0", "1"],
        "drawn_cards_drop" => [""],
        "hand" => %{
          "0" => %{"type" => "2", "colour" => "green", "count" => "2"},
          "1" => %{"type" => "wild", "count" => "1"}
        },
        "hand_sort" => ["0", "1"],
        "hand_drop" => [""]
      }
    }
  end

  defp bool_param(true), do: "true"
  defp bool_param(false), do: "false"
end
