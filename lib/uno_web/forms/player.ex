defmodule UnoWeb.Forms.Player do
  @moduledoc """
  One entry in the `players` list.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field :id, :string
    field :name, :string
  end

  def changeset(player \\ %__MODULE__{}, attrs) do
    player
    |> cast(attrs, [:id, :name])
    |> validate_required([:id, :name])
    |> validate_format(:id, ~r/^[a-zA-Z0-9]+$/, message: "must be alphanumeric")
    |> validate_length(:name, max: 20)
  end
end
