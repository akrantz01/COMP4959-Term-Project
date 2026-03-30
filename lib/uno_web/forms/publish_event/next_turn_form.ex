defmodule UnoWeb.Forms.PublishEvent.NextTurnForm do
  @moduledoc """
  Form module for the NextTurn event.

  Flattens compound types (top_card, chain) into individual form fields
  and reconstructs the event struct on submission.
  """

  import Ecto.Changeset

  alias UnoWeb.Forms.PublishEventForm

  @types %{
    sequence: :integer,
    player_id: :string,
    top_card_colour: :string,
    top_card_type: :string,
    direction: :string,
    vulnerable_player_id: :string,
    skipped: :boolean,
    chain_enabled: :boolean,
    chain_type: :string,
    chain_amount: :integer
  }

  @defaults %{
    sequence: 0,
    player_id: "",
    top_card_colour: "",
    top_card_type: "",
    direction: "",
    vulnerable_player_id: "",
    skipped: false,
    chain_enabled: false,
    chain_type: "",
    chain_amount: nil
  }

  def new, do: changeset() |> to_form()

  def changeset(params \\ %{}) do
    {@defaults, @types}
    |> cast(params, Map.keys(@types))
    |> validate_required([:sequence, :player_id, :top_card_colour, :top_card_type, :direction])
    |> validate_number(:sequence, greater_than_or_equal_to: 0)
    |> validate_inclusion(:top_card_colour, PublishEventForm.colours())
    |> validate_inclusion(:top_card_type, PublishEventForm.card_types())
    |> validate_inclusion(:direction, PublishEventForm.directions())
    |> validate_chain()
  end

  def to_form(changeset), do: Phoenix.Component.to_form(changeset, as: "publish")

  def parse(params), do: params |> changeset() |> apply_action(:insert)

  @doc "Converts parsed form data into a `Uno.Events.NextTurn` struct."
  def to_event(data) do
    %Uno.Events.NextTurn{
      sequence: data.sequence,
      player_id: data.player_id,
      top_card:
        PublishEventForm.to_played_card(%{
          colour: data.top_card_colour,
          type: data.top_card_type
        }),
      direction: String.to_existing_atom(data.direction),
      vulnerable_player_id: non_empty(data.vulnerable_player_id),
      skipped: data.skipped,
      chain: build_chain(data)
    }
  end

  defp validate_chain(changeset) do
    if get_field(changeset, :chain_enabled) do
      changeset
      |> validate_required([:chain_type, :chain_amount])
      |> validate_inclusion(:chain_type, PublishEventForm.chain_types())
      |> validate_number(:chain_amount, greater_than: 0)
    else
      changeset
    end
  end

  defp build_chain(%{chain_enabled: true, chain_type: type, chain_amount: amount}) do
    %{type: String.to_existing_atom(type), amount: amount}
  end

  defp build_chain(_), do: nil

  defp non_empty(""), do: nil
  defp non_empty(nil), do: nil
  defp non_empty(value), do: value
end
