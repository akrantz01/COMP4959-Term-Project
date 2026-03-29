defmodule UnoWeb.Forms.SubscriptionForm do
  @moduledoc """
  A form for managing a devtools PubSub subscription to a room/game pair
  """

  import Ecto.Changeset

  @types %{id: :string, room: :boolean, game: :boolean}

  def new(), do: changeset() |> to_form()

  def changeset(params \\ %{}) do
    {%{id: "", room: false, game: false}, @types}
    |> cast(params, Map.keys(@types))
    |> validate_required([:id])
    |> validate_format(:id, ~r/^[a-zA-Z0-9]+$/, message: "must be alphanumeric")
  end

  def to_form(changeset), do: Phoenix.Component.to_form(changeset, as: "subscription")

  def parse(params), do: params |> changeset() |> apply_action(:insert)
end
