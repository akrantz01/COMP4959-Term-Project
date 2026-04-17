defmodule UnoWeb.Forms.Event.GameEnded do
  @moduledoc """
  A game ended event form
  """
  @behaviour UnoWeb.Forms.Event

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field :winner_id, :string
  end

  @impl true
  def new(), do: %__MODULE__{}

  @impl true
  def changeset(game_ended \\ %__MODULE__{}, attrs) do
    game_ended
    |> cast(attrs, [:winner_id])
    |> validate_required([:winner_id])
    |> validate_format(:winner_id, ~r/^[a-zA-Z0-9]+$/, message: "must be alphanumeric")
  end

  @impl true
  def to_event(%__MODULE__{} = form) do
    %Uno.Events.GameEnded{
      winner_id: form.winner_id
    }
  end

  @impl true
  def from_event(%Uno.Events.GameEnded{} = e),
    do: %{"winner_id" => e.winner_id}
end
