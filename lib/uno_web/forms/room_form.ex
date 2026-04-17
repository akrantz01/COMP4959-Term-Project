defmodule UnoWeb.Forms.RoomForm do
  @moduledoc """
  A form for managing the state of the room.

  Should be removed once more interactions are implemented.
  """

  import Ecto.Changeset

  @types %{
    state: Ecto.ParameterizedType.init(Ecto.Enum, values: [:lobby, :game]),
    player_id: :string
  }

  def new(params \\ %{}), do: changeset(params) |> to_form()

  def changeset(params \\ %{}) do
    {%{state: :lobby, player_id: Nanoid.generate()}, @types}
    |> cast(params, Map.keys(@types))
    |> validate_required([:state, :player_id])
    |> validate_format(:player_id, ~r/^[a-zA-Z0-9]+$/, message: "must be alphanumeric")
  end

  def to_form(changeset), do: Phoenix.Component.to_form(changeset, as: "room")

  def parse(changeset), do: apply_action(changeset, :insert)
end
