defmodule UnoWeb.Forms.PublishEvent.CardBuilderForm do
  @moduledoc """
  A form for adding a single card to the card list in the devtools publisher.
  """

  import Ecto.Changeset

  alias UnoWeb.Forms.PublishEventForm

  @types %{colour: :string, type: :string}

  def new, do: changeset() |> to_form()

  def changeset(params \\ %{}) do
    {%{colour: "", type: ""}, @types}
    |> cast(params, Map.keys(@types))
    |> validate_required([:colour, :type])
    |> validate_inclusion(:colour, PublishEventForm.colours())
    |> validate_inclusion(:type, PublishEventForm.card_types())
  end

  def to_form(changeset), do: Phoenix.Component.to_form(changeset, as: "card_builder")

  def parse(params), do: params |> changeset() |> apply_action(:insert)
end
