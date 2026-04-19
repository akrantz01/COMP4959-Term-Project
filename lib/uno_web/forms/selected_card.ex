defmodule UnoWeb.Forms.SelectedCard do
  @moduledoc """
  A card being selected from a player's hand
  """
  alias UnoWeb.Forms.Card

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    embeds_one :card, Card

    field :index, :integer
  end

  def parse(%{"colour" => colour, "type" => type, "index" => index}),
    do: parse(%{"index" => index, "card" => %{"colour" => colour, "type" => type}})

  def parse(params), do: changeset(params) |> apply_action(:insert)

  def changeset(selected \\ %__MODULE__{}, attrs) do
    selected
    |> cast(attrs, [:index])
    |> validate_required([:index])
    |> validate_number(:index, greater_than_or_equal_to: 1)
    |> cast_embed(:card, with: &Card.played_changeset/2, required: true)
  end
end
