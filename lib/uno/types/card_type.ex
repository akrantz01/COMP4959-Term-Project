defmodule Uno.Types.CardType do
  @moduledoc """
  A custom Ecto type for representing an UNO card type.

  Accepts integers `0..9`, `:reverse`, `:skip`, and `:draw_2`. When the `:wilds` parameter is set to
  `true`, `:wild` and `:wild_draw_4` are also accepted.
  """

  use Ecto.ParameterizedType

  @default ~w(reverse skip draw_2)a
  @with_wilds ~w(reverse skip draw_2 wild wild_draw_4)a
  @range 0..9

  @impl true
  def init(opts), do: %{wilds: Keyword.get(opts, :wilds, false)}

  @impl true
  def type(_params), do: :string

  @impl true
  def cast(nil, _params), do: {:ok, nil}
  def cast(val, _params) when is_integer(val) and val in @range, do: {:ok, val}
  def cast(val, %{wilds: false}) when is_atom(val) and val in @default, do: {:ok, val}
  def cast(val, %{wilds: true}) when is_atom(val) and val in @with_wilds, do: {:ok, val}

  def cast(val, params) when is_binary(val) do
    case Integer.parse(val) do
      {int, ""} ->
        cast(int, params)

      _ ->
        safe_to_atom(val) |> cast(params)
    end
  end

  def cast(_, _), do: :error

  @impl true
  def dump(nil, _dumper, _params), do: {:ok, nil}

  def dump(val, _dumper, _params) when is_integer(val) and val in @range,
    do: {:ok, Integer.to_string(val)}

  def dump(val, _dumper, %{wilds: false}) when is_atom(val) and val in @default,
    do: {:ok, Atom.to_string(val)}

  def dump(val, _dumper, %{wilds: true}) when is_atom(val) and val in @with_wilds,
    do: {:ok, Atom.to_string(val)}

  def dump(_, _, _), do: :error

  @impl true
  def load(val, _loader, params) when is_binary(val), do: cast(val, params)

  defp safe_to_atom(val) do
    String.to_existing_atom(val)
  rescue
    ArgumentError -> nil
  end
end
