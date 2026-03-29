defmodule UnoWeb.Forms.PublishEvent.CardBuilderForm do
  @moduledoc """
  A form for adding a single card to the card list in the devtools publisher.

  Accepts an optional `mode` to control wild card colour validation:

  - `:played` (default) — colour is always required (wilds are played with a chosen colour)
  - `:drawn` — colour is required for non-wild cards, forbidden for wild cards
  """

  import Ecto.Changeset

  alias UnoWeb.Forms.PublishEventForm

  @types %{colour: :string, type: :string}
  @wild_types ~w(wild wild_draw_4)

  def new(mode \\ :played), do: changeset(%{}, mode) |> to_form()

  def changeset(params \\ %{}, mode \\ :played) do
    {%{colour: "", type: ""}, @types}
    |> cast(params, Map.keys(@types))
    |> validate_required([:type])
    |> validate_inclusion(:type, PublishEventForm.card_types())
    |> validate_colour(mode)
  end

  defp validate_colour(changeset, :drawn) do
    if get_field(changeset, :type) in @wild_types do
      force_change(changeset, :colour, "")
    else
      changeset
      |> validate_required([:colour])
      |> validate_inclusion(:colour, PublishEventForm.colours())
    end
  end

  defp validate_colour(changeset, :played) do
    changeset
    |> validate_required([:colour])
    |> validate_inclusion(:colour, PublishEventForm.colours())
  end

  def to_form(changeset), do: Phoenix.Component.to_form(changeset, as: "card_builder")

  def parse(params, mode \\ :played), do: params |> changeset(mode) |> apply_action(:insert)
end
