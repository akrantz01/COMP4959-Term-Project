defmodule UnoWeb.Forms.Card do
  @moduledoc """
  The possible representations of a card.

  The representations are:
  - held in hand: count for amount of each card, wildcards are colourless
  - drawn from the deck: wildcards are colourless
  - placed down: wildcards are resolved to a colour
  """
  alias Uno.Types.CardType

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field :colour, Ecto.Enum, values: [:red, :green, :blue, :yellow]
    field :type, CardType, wilds: true
    field :count, :integer, default: 1
  end

  def hand_changeset(card \\ %__MODULE__{}, attrs) do
    card
    |> cast(attrs, [:colour, :type, :count])
    |> validate_required([:type, :count])
    |> validate_number(:count, greater_than: 0)
    |> validate_wildcard()
  end

  def drawn_changeset(card \\ %__MODULE__{}, attrs) do
    card |> cast(attrs, [:colour, :type]) |> validate_required([:type]) |> validate_wildcard()
  end

  def played_changeset(card \\ %__MODULE__{}, attrs) do
    card |> cast(attrs, [:colour, :type]) |> validate_required([:colour, :type])
  end

  def format(:hand, %__MODULE__{type: type, colour: nil}), do: type
  def format(:hand, %__MODULE__{type: type, colour: colour}), do: {colour, type}

  def format(:played, %__MODULE__{type: type, colour: colour}) when type in ~w(wild wild_draw_4)a,
    do: {type, colour}

  def format(:played, %__MODULE__{type: type, colour: colour}), do: {colour, type}

  def unformat(:hand, type) when is_atom(type),
    do: %{"type" => to_string(type)}

  def unformat(:hand, {colour, type}),
    do: %{"type" => to_string(type), "colour" => to_string(colour)}

  def unformat(:played, {type, colour}) when type in ~w(wild wild_draw_4)a,
    do: %{"type" => to_string(type), "colour" => to_string(colour)}

  def unformat(:played, {colour, type}),
    do: %{"type" => to_string(type), "colour" => to_string(colour)}

  defp validate_wildcard(changeset) do
    is_wild = get_field(changeset, :type) in ~w(wild wild_draw_4)a
    missing_colour = is_nil(get_field(changeset, :colour))

    cond do
      is_wild && !missing_colour ->
        add_error(changeset, :colour, "must be blank for wild cards")

      !is_wild && missing_colour ->
        add_error(changeset, :colour, "is required for non-wild cards")

      true ->
        changeset
    end
  end
end
