defmodule UnoWeb.Forms.Event.NextTurn do
  @moduledoc """
  A next turn event form
  """
  @behaviour UnoWeb.Forms.Event

  alias UnoWeb.Forms.{Card, Chain}

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field :sequence, :integer, default: 0
    field :player_id, :string
    field :direction, Ecto.Enum, values: [:ltr, :rtl], default: :ltr
    field :vulnerable_player_id, :string
    field :skipped, :boolean, default: false

    embeds_one :top_card, Card, on_replace: :update

    field :has_chain, :boolean, default: false
    embeds_one :chain, Chain, on_replace: :update
  end

  @impl true
  def new(), do: %__MODULE__{}

  @impl true
  def changeset(next_turn \\ %__MODULE__{}, attrs) do
    next_turn
    |> cast(attrs, [
      :sequence,
      :player_id,
      :direction,
      :vulnerable_player_id,
      :skipped,
      :has_chain
    ])
    |> validate_required([:sequence, :player_id, :direction, :skipped])
    |> validate_format(:player_id, ~r/^[a-zA-Z0-9]+$/, message: "must be alphanumeric")
    |> validate_format(:vulnerable_player_id, ~r/^[a-zA-Z0-9]+$/, message: "must be alphanumeric")
    |> cast_embed(:top_card, with: &Card.played_changeset/2, required: true)
    |> cast_embed(:chain)
  end

  @impl true
  def to_event(%__MODULE__{} = form) do
    %Uno.Events.NextTurn{
      sequence: form.sequence,
      player_id: form.player_id,
      top_card: Card.format(:played, form.top_card),
      direction: form.direction,
      vulnerable_player_id: form.vulnerable_player_id,
      skipped: form.skipped,
      chain: Chain.format(form.chain)
    }
  end
end
