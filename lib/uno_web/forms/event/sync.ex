defmodule UnoWeb.Forms.Event.Sync do
  @moduledoc """
  A sync event form
  """
  @behaviour UnoWeb.Forms.Event

  alias UnoWeb.Forms.{Card, Chain, Hand, Player}

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field :sequence, :integer, default: 0
    field :direction, Ecto.Enum, values: [:ltr, :rtl], default: :ltr
    field :vulnerable_player_id, :string

    embeds_one :top_card, Card, on_replace: :update

    field :has_chain, :boolean, default: false
    embeds_one :chain, Chain, on_replace: :update

    embeds_many :players, Player, on_replace: :delete
    embeds_many :hands, Hand, on_replace: :delete
  end

  @impl true
  def new(), do: %__MODULE__{}

  @impl true
  def changeset(sync \\ %__MODULE__{}, attrs) do
    sync
    |> cast(attrs, [:sequence, :direction, :vulnerable_player_id, :has_chain])
    |> validate_required([:sequence, :direction])
    |> validate_number(:sequence, greater_than_or_equal_to: 0)
    |> validate_format(:vulnerable_player_id, ~r/^[a-zA-Z0-9]+$/, message: "must be alphanumeric")
    |> cast_embed(:top_card, with: &Card.played_changeset/2, required: true)
    |> cast_embed(:chain)
    |> cast_embed(:players, required: true, sort_param: :players_sort, drop_param: :players_drop)
    |> cast_embed(:hands, required: true, sort_param: :hands_sort, drop_param: :hands_drop)
  end

  @impl true
  def to_event(%__MODULE__{} = form) do
    %Uno.Events.Sync{
      sequence: form.sequence,
      direction: form.direction,
      vulnerable_player_id: form.vulnerable_player_id,
      top_card: Card.format(:played, form.top_card),
      chain: if(form.has_chain, do: Chain.format(form.chain), else: nil),
      players: Enum.map(form.players, &{&1.id, &1.name}),
      hands:
        Map.new(form.hands, fn hand ->
          {hand.player_id,
           Map.new(hand.cards, fn card -> {Card.format(:hand, card), card.count} end)}
        end)
    }
  end

  @impl true
  def from_event(%Uno.Events.Sync{} = e) do
    params = %{
      "sequence" => e.sequence,
      "direction" => to_string(e.direction),
      "vulnerable_player_id" => e.vulnerable_player_id,
      "top_card" => Card.unformat(:played, e.top_card),
      "players" => Enum.map(e.players, fn {id, name} -> %{"id" => id, "name" => name} end),
      "hands" =>
        Enum.map(e.hands, fn {player_id, cards} ->
          %{
            "player_id" => player_id,
            "cards" =>
              Enum.map(cards, fn {card, count} ->
                Card.unformat(:hand, card) |> Map.put("count", count)
              end)
          }
        end)
    }

    case e.chain do
      nil -> Map.put(params, "has_chain", false)
      chain -> params |> Map.put("has_chain", true) |> Map.put("chain", Chain.unformat(chain))
    end
  end
end
