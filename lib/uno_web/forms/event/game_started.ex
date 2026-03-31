defmodule UnoWeb.Forms.Event.GameStarted do
  @moduledoc """
  A game started event form
  """
  @behaviour UnoWeb.Forms.Event

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field :game_id, :string
  end

  @impl true
  def new(), do: %__MODULE__{}

  @impl true
  def changeset(game_started \\ %__MODULE__{}, attrs) do
    game_started
    |> cast(attrs, [:game_id])
    |> validate_required([:game_id])
    |> validate_format(:game_id, ~r/^[a-zA-Z0-9]+$/, message: "must be alphanumeric")
  end

  @impl true
  def to_event(%__MODULE__{} = form) do
    %Uno.Events.GameStarted{
      game_id: form.game_id
    }
  end
end
