defmodule UnoWeb.Forms.PublishEvent.HandEntryBuilderForm do
  @moduledoc """
  A form for adding a single hand entry (card + count) to the hand builder in the devtools publisher.
  """

  import Ecto.Changeset

  alias UnoWeb.Forms.PublishEventForm

  @types %{colour: :string, type: :string, count: :integer}

  def new, do: changeset() |> to_form()

  def changeset(params \\ %{}) do
    {%{colour: "", type: "", count: 1}, @types}
    |> cast(params, Map.keys(@types))
    |> validate_required([:type, :count])
    |> validate_inclusion(:type, PublishEventForm.card_types())
    |> validate_number(:count, greater_than_or_equal_to: 0)
    |> PublishEventForm.validate_colour_for_wild()
  end

  def to_form(changeset), do: Phoenix.Component.to_form(changeset, as: "hand_entry_builder")
end
