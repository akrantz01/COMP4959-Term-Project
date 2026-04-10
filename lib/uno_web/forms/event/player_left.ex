defmodule UnoWeb.Forms.Event.PlayerLeft do
  @moduledoc """
  A player left event form
  """
  @behaviour UnoWeb.Forms.Event

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field :player_id, :string
  end

  @impl true
  def new(), do: %__MODULE__{}

  @impl true
  def changeset(player_left \\ %__MODULE__{}, attrs) do
    player_left
    |> cast(attrs, [:player_id])
    |> validate_required([:player_id])
    |> validate_format(:player_id, ~r/^[a-zA-Z0-9]+$/, message: "must be alphanumeric")
  end

  @impl true
  def to_event(%__MODULE__{} = form) do
    %Uno.Events.PlayerLeft{
      player_id: form.player_id
    }
  end
end
