defmodule UnoWeb.Forms.PublishEvent.EventSelectorForm do
  @moduledoc """
  A form for selecting which event type to publish from the devtools.
  """

  import Ecto.Changeset

  @event_types ~w(player_joined player_left game_started game_ended next_turn cards_played cards_drawn)

  @types %{event_type: :string}

  def new, do: changeset() |> to_form()

  def changeset(params \\ %{}) do
    {%{event_type: ""}, @types}
    |> cast(params, Map.keys(@types))
    |> validate_inclusion(:event_type, @event_types)
  end

  def to_form(changeset), do: Phoenix.Component.to_form(changeset, as: "event_selector")

  def parse(params), do: params |> changeset() |> apply_action(:insert)
end
