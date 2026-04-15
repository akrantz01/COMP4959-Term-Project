defmodule UnoWeb.CardComponents do
  @moduledoc """
  Provides a UI component for rendering UNO cards.

  ## Card types

  Accepts any value matching the game's card types:

      # Hand cards
      {colour, card_type}   e.g. {:red, 7}, {:blue, :skip}
      :wild
      :wild_draw_4

      # Played cards
      {colour, card_type}   (same as hand)
      {:wild, colour}       e.g. {:wild, :blue}
      {:wild_draw_4, colour} e.g. {:wild_draw_4, :green}

  ## Usage

      <.uno_card card={{:red, 7}} />
      <.uno_card card={:wild} />
      <.uno_card card={{:wild, :blue}} />
  """
  use Phoenix.Component

  @colors %{
    red: %{
      bg: "bg-[#d72600]",
      text: "text-[#d72600]",
      border: "border-[#d72600]",
      glow: "shadow-[0_0_0_4px_#d72600,0_6px_20px_rgba(215,38,0,0.4)]"
    },
    green: %{
      bg: "bg-[#379711]",
      text: "text-[#379711]",
      border: "border-[#379711]",
      glow: "shadow-[0_0_0_4px_#379711,0_6px_20px_rgba(55,151,17,0.4)]"
    },
    blue: %{
      bg: "bg-[#0956bf]",
      text: "text-[#0956bf]",
      border: "border-[#0956bf]",
      glow: "shadow-[0_0_0_4px_#0956bf,0_6px_20px_rgba(9,86,191,0.4)]"
    },
    yellow: %{
      bg: "bg-[#eac500]",
      text: "text-[#eac500]",
      border: "border-[#eac500]",
      glow: "shadow-[0_0_0_4px_#eac500,0_6px_20px_rgba(234,197,0,0.4)]"
    }
  }

  @sizes %{
    md: ["w-30 h-45"],
    lg: ["w-40 h-60"]
  }

  attr :size, :atom, values: ~w(md lg)a, default: :md
  attr :class, :string, default: nil
  attr :rest, :global

  def flipped_card(assigns) do
    assigns = assign(assigns, :size, @sizes[assigns.size])

    ~H"""
    <div
      class={[
        @size,
        "rounded-2xl relative select-none",
        "bg-black",
        "shadow-[0_2px_4px_rgba(0,0,0,0.3),0_6px_16px_rgba(0,0,0,0.2),inset_0_1px_0_rgba(255,255,255,0.15)]",
        @class
      ]}
      {@rest}
    >
      <div class="absolute top-4.5 bottom-4.5 left-3.5 right-3.5 [border-radius:50%/46%] -rotate-12 bg-[#d72600] flex items-center justify-center overflow-hidden shadow-[0_0_0_3px_rgba(255,255,255,0.15)]">
        <span class="transform-[perspective(1px)_rotate(78deg)] text-4xl font-black text-white tracking-widest [text-shadow:2px_2px_4px_rgba(0,0,0,0.4)]">
          UNO
        </span>
      </div>
    </div>
    """
  end

  attr :card, :any, required: true
  attr :size, :atom, values: ~w(md lg)a, default: :md
  attr :class, :string, default: nil
  attr :rest, :global

  def uno_card(assigns) do
    %{wild?: wild?, played?: played?, color: color, value: value} = parse_card(assigns.card)
    c = color && @colors[color]

    assigns =
      assign(assigns,
        wild?: wild?,
        played?: played?,
        size: @sizes[assigns.size],
        color: color,
        c: c,
        value: value,
        corner: label(value)
      )

    ~H"""
    <div
      class={[
        @size,
        "rounded-2xl relative cursor-pointer select-none",
        "transition-all duration-200 ease-out",
        "shadow-[0_2px_4px_rgba(0,0,0,0.3),0_6px_16px_rgba(0,0,0,0.2),inset_0_1px_0_rgba(255,255,255,0.15)]",
        "hover:-translate-y-2 hover:scale-103",
        "hover:shadow-[0_12px_28px_rgba(0,0,0,0.35),0_4px_8px_rgba(0,0,0,0.2),inset_0_1px_0_rgba(255,255,255,0.15)]",
        if(@wild?, do: "bg-[#1a1a1a]", else: @c.bg),
        @played? && @c.glow,
        @played? && ["border-4", @c.border],
        @class
      ]}
      {@rest}
    >
      <.wild_background :if={@wild?} faded={@played?} />

      <div class={[
        "absolute top-4.5 bottom-4.5 left-3.5 right-3.5 [border-radius:50%/46%] -rotate-12",
        if(@wild?,
          do: "bg-black/80",
          else: if(@color == :yellow, do: "bg-white/80", else: "bg-white/[0.92]")
        ),
        if(@wild?,
          do: "shadow-[0_0_0_3px_rgba(255,255,255,0.1)]",
          else: "shadow-[0_0_0_3px_rgba(0,0,0,0.08)]"
        )
      ]} />

      <span class="absolute text-lg text-white leading-none z-3 [text-shadow:1px_1px_2px_rgba(0,0,0,0.35)] top-2.5 left-2.5">
        {@corner}
      </span>
      <span class="absolute text-lg text-white leading-none z-3 [text-shadow:1px_1px_2px_rgba(0,0,0,0.35)] bottom-2.5 right-2.5 rotate-180">
        {@corner}
      </span>

      <div class="absolute inset-0 flex items-center justify-center z-2 leading-none">
        <.center center={@value} color={@color} />
      </div>
    </div>
    """
  end

  defp parse_card({wild, chosen})
       when wild in [:wild, :wild_draw_4] and chosen in [:red, :green, :blue, :yellow],
       do: %{wild?: true, played?: true, color: chosen, value: wild}

  defp parse_card(wild) when wild in [:wild, :wild_draw_4],
    do: %{wild?: true, played?: false, color: nil, value: wild}

  defp parse_card({color, value}) when color in [:red, :green, :blue, :yellow],
    do: %{wild?: false, played?: false, color: color, value: value}

  attr :center, :any, required: true
  attr :color, :atom, default: nil

  defp center(%{center: n} = assigns) when is_integer(n) do
    assigns = assign(assigns, :c, @colors[assigns.color])

    ~H"""
    <span class={[
      "text-7xl [-webkit-text-stroke:3px_rgba(0,0,0,0.12)]",
      "[filter:drop-shadow(0_2px_2px_rgba(0,0,0,0.15))]",
      @c.text
    ]}>
      {label(@center)}
    </span>
    """
  end

  defp center(%{center: :skip} = assigns) do
    assigns = assign(assigns, :c, @colors[assigns.color])

    ~H"""
    <span class={["text-6xl text-center leading-none", @c.text]}>{label(@center)}</span>
    """
  end

  defp center(%{center: :reverse} = assigns) do
    assigns = assign(assigns, :c, @colors[assigns.color])

    ~H"""
    <span class={["text-7xl text-center leading-none", @c.text]}>{label(@center)}</span>
    """
  end

  defp center(%{center: :draw_2} = assigns) do
    assigns = assign(assigns, :c, @colors[assigns.color])

    ~H"""
    <div class={[@c.text, "text-center"]}>
      <span class="text-4xl">{label(@center)}</span>
      <.small_cards count={2} bg={@c.bg} />
    </div>
    """
  end

  defp center(%{center: :wild_draw_4} = assigns) do
    assigns =
      assign(
        assigns,
        :c,
        if(assigns.color, do: @colors[assigns.color], else: %{text: "text-white", bg: "bg-white"})
      )

    ~H"""
    <div class={[@c.text, "text-center"]}>
      <span class="text-4xl">{label(@center)}</span>
      <.small_cards count={4} bg={@c.bg} />
    </div>
    """
  end

  defp center(%{center: :wild} = assigns) do
    assigns =
      assign(
        assigns,
        :c,
        if(assigns.color, do: @colors[assigns.color], else: %{text: "text-white"})
      )

    ~H"""
    <span class={["text-4xl text-center leading-none", @c.text]}>
      WILD
    </span>
    """
  end

  attr :bg, :string, required: true
  attr :count, :integer, required: true

  defp small_cards(assigns) do
    ~H"""
    <div class="grid grid-cols-2 auto-rows-min gap-0.5 justify-center mt-1">
      <div :for={_ <- 1..@count} class={["w-5 h-7 rounded-sm border-2 border-black/15", @bg]} />
    </div>
    """
  end

  attr :faded, :boolean, default: false

  @wild_quadrants [
    {"top-0 left-0", :red},
    {"top-0 right-0", :blue},
    {"bottom-0 left-0", :yellow},
    {"bottom-0 right-0", :green}
  ]

  defp wild_background(assigns) do
    quadrants = Enum.map(@wild_quadrants, fn {pos, color} -> {pos, @colors[color].bg} end)
    assigns = assign(assigns, :quadrants, quadrants)

    ~H"""
    <div class="absolute inset-0 rounded-2xl overflow-hidden">
      <div
        :for={{pos, bg} <- @quadrants}
        class={["absolute w-1/2 h-1/2", pos, bg, @faded && "opacity-25"]}
      />
    </div>
    """
  end

  defp label(n) when is_integer(n), do: Integer.to_string(n)
  defp label(:skip), do: "⊘"
  defp label(:reverse), do: "⇄"
  defp label(:draw_2), do: "+2"
  defp label(:wild), do: "W"
  defp label(:wild_draw_4), do: "+4"
end
