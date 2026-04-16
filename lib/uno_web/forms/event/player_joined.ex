defmodule UnoWeb.Forms.Event.PlayerJoined do
  @moduledoc """
  A player joined event form
  """
  @behaviour UnoWeb.Forms.Event

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field :player_id, :string
    field :name, :string
  end

  @impl true
  def new(), do: %__MODULE__{}

  @impl true
  def changeset(player_joined \\ %__MODULE__{}, attrs) do
    player_joined
    |> cast(attrs, [:player_id, :name])
    |> validate_required([:player_id, :name])
    |> validate_format(:player_id, ~r/^[a-zA-Z0-9]+$/, message: "must be alphanumeric")
    |> validate_length(:name, max: 20)
  end

  @impl true
  def to_event(%__MODULE__{} = form) do
    %Uno.Events.PlayerJoined{
      player_id: form.player_id,
      name: form.name
    }
  end

  @impl true
  def from_event(%Uno.Events.PlayerJoined{} = e),
    do: %{"player_id" => e.player_id, "name" => e.name}
end
