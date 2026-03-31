defmodule UnoWeb.Forms.Chain do
  @moduledoc """
  The current state of the draw chain.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field :type, Ecto.Enum, values: [:draw_2, :wild_draw_4]
    field :amount, :integer
  end

  def changeset(chain \\ %__MODULE__{}, attrs) do
    chain
    |> cast(attrs, [:type, :amount])
    |> validate_required([:type, :amount])
    |> validate_number(:amount, greater_than: 0)
  end

  def format(nil), do: nil
  def format(%__MODULE__{type: type, amount: amount}), do: %{type: type, amount: amount}
end
