defmodule UnoWeb.Forms.PublishEvent.HandEntryBuilderForm do
  @moduledoc """
  A form for adding a single hand entry (card + count) to the hand builder in the devtools publisher.
  """

  import Ecto.Changeset

  alias UnoWeb.Forms.PublishEventForm

  @types %{colour: :string, type: :string, count: :integer}
  @wild_types ~w(wild wild_draw_4)

  def new, do: changeset() |> to_form()

  def changeset(params \\ %{}) do
    {%{colour: "", type: "", count: 1}, @types}
    |> cast(params, Map.keys(@types))
    |> validate_required([:type, :count])
    |> validate_inclusion(:type, PublishEventForm.card_types())
    |> validate_number(:count, greater_than_or_equal_to: 0)
    |> validate_colour_unless_wild()
  end

  defp validate_colour_unless_wild(changeset) do
    if get_field(changeset, :type) in @wild_types do
      force_change(changeset, :colour, "")
    else
      changeset
      |> validate_required([:colour])
      |> validate_inclusion(:colour, PublishEventForm.colours())
    end
  end

  def to_form(changeset), do: Phoenix.Component.to_form(changeset, as: "hand_entry_builder")
end
