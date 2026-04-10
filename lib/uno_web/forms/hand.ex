defmodule UnoWeb.Forms.Hand do
  @moduledoc """
  One entry in the `hands` map, keyed by player id.
  """
  alias UnoWeb.Forms.Card

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field :player_id, :string

    embeds_many :cards, Card, on_replace: :delete
  end

  def changeset(hand \\ %__MODULE__{}, attrs) do
    hand
    |> cast(attrs, [:player_id])
    |> validate_required([:player_id])
    |> validate_format(:player_id, ~r/^[a-zA-Z0-9]+$/, message: "must be alphanumeric")
    |> cast_embed(:cards,
      with: &Card.hand_changeset/2,
      sort_param: :cards_sort,
      drop_param: :cards_drop
    )
  end
end
