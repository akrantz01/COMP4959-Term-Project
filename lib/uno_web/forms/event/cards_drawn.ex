defmodule UnoWeb.Forms.Event.CardsDrawn do
  @moduledoc """
  A cards drawn event form
  """
  @behaviour UnoWeb.Forms.Event

  alias UnoWeb.Forms.Card

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field :player_id, :string

    embeds_many :drawn_cards, Card, on_replace: :delete
    embeds_many :hand, Card, on_replace: :delete
  end

  @impl true
  def new(), do: %__MODULE__{}

  @impl true
  def changeset(cards_drawn \\ %__MODULE__{}, attrs) do
    cards_drawn
    |> cast(attrs, [:player_id])
    |> validate_required([:player_id])
    |> cast_embed(:drawn_cards,
      with: &Card.drawn_changeset/2,
      sort_param: :drawn_cards_sort,
      drop_param: :drawn_cards_drop
    )
    |> cast_embed(:hand,
      with: &Card.hand_changeset/2,
      sort_param: :hand_sort,
      drop_param: :hand_drop
    )
  end

  @impl true
  def to_event(%__MODULE__{} = form) do
    %Uno.Events.CardsDrawn{
      player_id: form.player_id,
      drawn_cards: Enum.map(form.drawn_cards, &Card.format(:hand, &1)),
      hand: Map.new(form.hand, &{Card.format(:hand, &1), &1.count})
    }
  end

  @impl true
  def from_event(%Uno.Events.CardsDrawn{} = e) do
    %{
      "player_id" => e.player_id,
      "drawn_cards" => Enum.map(e.drawn_cards, &Card.unformat(:hand, &1)),
      "hand" =>
        Enum.map(e.hand, fn {card, count} ->
          Card.unformat(:hand, card) |> Map.put("count", count)
        end)
    }
  end
end
