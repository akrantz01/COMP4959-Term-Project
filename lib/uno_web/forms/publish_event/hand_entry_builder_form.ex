defmodule UnoWeb.Forms.PublishEvent.HandEntryBuilderForm do
  @moduledoc """
  A form for adding a single hand entry (card + count) to the hand builder in the devtools publisher.

  Supports a `:sync` mode that requires a `player_id` field for grouping entries by player.
  """

  import Ecto.Changeset

  alias UnoWeb.Forms.PublishEventForm

  @types %{player_id: :string, colour: :string, type: :string, count: :integer}

  def new(mode \\ :default), do: changeset(%{}, mode) |> to_form()

  def changeset(params \\ %{}, mode \\ :default) do
    {%{player_id: "", colour: "", type: "", count: 1}, @types}
    |> cast(params, Map.keys(@types))
    |> validate_required(required_fields(mode))
    |> validate_inclusion(:type, PublishEventForm.card_types())
    |> validate_number(:count, greater_than_or_equal_to: 0)
    |> PublishEventForm.validate_colour_for_wild()
  end

  def to_form(changeset), do: Phoenix.Component.to_form(changeset, as: "hand_entry_builder")

  defp required_fields(:sync), do: [:player_id, :type, :count]
  defp required_fields(_), do: [:type, :count]
end
