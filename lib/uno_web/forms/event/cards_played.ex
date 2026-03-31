defmodule UnoWeb.Forms.Event.CardsPlayed do
  @moduledoc """
  A cards played event form
  """
  @behaviour UnoWeb.Forms.Event

  alias UnoWeb.Forms.Card

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field :player_id, :string

    embeds_many :played_cards, Card, on_replace: :delete
    embeds_many :hand, Card, on_replace: :delete
  end

  @impl true
  def new(), do: %__MODULE__{}

  @impl true
  def changeset(cards_played \\ %__MODULE__{}, attrs) do
    cards_played
    |> cast(attrs, [:player_id])
    |> validate_required([:player_id])
    |> cast_embed(:played_cards,
      with: &Card.played_changeset/2,
      sort_param: :played_cards_sort,
      drop_param: :played_cards_drop
    )
    |> cast_embed(:hand,
      with: &Card.hand_changeset/2,
      sort_param: :hand_sort,
      drop_param: :hand_drop
    )
  end

  @impl true
  def to_event(%__MODULE__{} = form) do
    %Uno.Events.CardsPlayed{
      player_id: form.player_id,
      played_cards: Enum.map(form.played_cards, &Card.format(:played, &1)),
      hand: Map.new(form.hand, &{Card.format(:hand, &1), &1.count})
    }
  end
end
