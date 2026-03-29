defmodule UnoWeb.Forms.PublishEvent.SyncForm do
  @moduledoc """
  Form module for the Sync event.

  Flattens compound types (top_card, chain) into individual form fields
  and reconstructs the event struct on submission. Hands are built from
  the hand entry list, grouped by player ID.
  """

  import Ecto.Changeset

  alias UnoWeb.Forms.PublishEventForm

  @types %{
    sequence: :integer,
    top_card_colour: :string,
    top_card_type: :string,
    direction: :string,
    vulnerable_player_id: :string,
    chain_enabled: :boolean,
    chain_type: :string,
    chain_amount: :integer
  }

  @defaults %{
    sequence: 0,
    top_card_colour: "",
    top_card_type: "",
    direction: "",
    vulnerable_player_id: "",
    chain_enabled: false,
    chain_type: "",
    chain_amount: nil
  }

  def new, do: changeset() |> to_form()

  def changeset(params \\ %{}) do
    {@defaults, @types}
    |> cast(params, Map.keys(@types))
    |> validate_required([:sequence, :top_card_colour, :top_card_type, :direction])
    |> validate_number(:sequence, greater_than_or_equal_to: 0)
    |> validate_inclusion(:top_card_colour, PublishEventForm.colours())
    |> validate_inclusion(:top_card_type, PublishEventForm.card_types())
    |> validate_inclusion(:direction, PublishEventForm.directions())
    |> PublishEventForm.validate_chain()
  end

  def to_form(changeset), do: Phoenix.Component.to_form(changeset, as: "publish")

  def parse(params), do: params |> changeset() |> apply_action(:insert)

  @doc "Converts parsed form data and hand entries into a `Uno.Events.Sync` struct."
  def to_event(data, hand_list) do
    %Uno.Events.Sync{
      sequence: data.sequence,
      top_card:
        PublishEventForm.to_played_card(%{
          colour: data.top_card_colour,
          type: data.top_card_type
        }),
      direction: String.to_existing_atom(data.direction),
      hands: build_hands(hand_list),
      vulnerable_player_id: non_empty(data.vulnerable_player_id),
      chain: PublishEventForm.build_chain(data)
    }
  end

  defp build_hands(hand_list) do
    hand_list
    |> Enum.group_by(& &1.player_id)
    |> Map.new(fn {pid, entries} -> {pid, PublishEventForm.build_hand(entries)} end)
  end

  defp non_empty(""), do: nil
  defp non_empty(nil), do: nil
  defp non_empty(value), do: value
end
