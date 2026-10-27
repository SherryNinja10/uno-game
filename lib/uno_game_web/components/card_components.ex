defmodule UnoGameWeb.CardComponents do
  use Phoenix.Component

  @doc """
  Renders an inline SVG UNO card based on state properties.
  Expects attributes that match the maps generated for `room_state.deck`.
  """
  attr :color, :string, required: true, doc: "red, blue, green, yellow, or black"
  attr :value, :string, required: true, doc: "0-9, skip, reverse, draw2, wild, wild_draw4"
  attr :class, :string, default: ""

  def uno_card(assigns) do
    ~H"""
    <svg
      viewBox="0 0 120 180"
      class={["w-32 h-48 drop-shadow-md transition-transform hover:-translate-y-4 cursor-pointer select-none", @class]}
      xmlns="http://www.w3.org/2000/svg"
    >
      <!-- Outer Card Border -->
      <rect x="0" y="0" width="120" height="180" rx="12" fill="white" />

      <!-- Inner Colored Background -->
      <rect x="4" y="4" width="112" height="172" rx="8" fill={hex_color(@color)} />

      <!-- Inner Asymmetric Oval -->
      <ellipse cx="60" cy="90" rx="42" ry="72" fill={hex_color(@color)} stroke="white" stroke-width="3" transform="rotate(-20 60 90)" />

      <!-- Center Main Value -->
      <text
        x="50%"
        y="54%"
        dominant-baseline="middle"
        text-anchor="middle"
        fill="white"
        font-family="sans-serif"
        font-weight="900"
        font-size={center_font_size(@value)}
        style="text-shadow: 2px 2px 0 #2d3748;"
        transform="rotate(-20 60 90)"
      >
        <%= display_value(@value) %>
      </text>

      <!-- Top Left Mini Value -->
      <text
        x="12"
        y="26"
        fill="white"
        font-family="sans-serif"
        font-weight="bold"
        font-size="18"
        style="text-shadow: 1px 1px 0 #2d3748;"
      >
        <%= display_value(@value) %>
      </text>

      <!-- Bottom Right Mini Value (Inverted) -->
      <text
        x="108"
        y="154"
        fill="white"
        font-family="sans-serif"
        font-weight="bold"
        font-size="18"
        style="text-shadow: 1px 1px 0 #2d3748;"
        transform="rotate(180 108 150)"
      >
        <%= display_value(@value) %>
      </text>
    </svg>
    """
  end

  # Maps logical state colors to exact UNO-style hex values
  defp hex_color("red"), do: "#ef4444"    # Tailwind red-500
  defp hex_color("blue"), do: "#3b82f6"   # Tailwind blue-500
  defp hex_color("green"), do: "#22c55e"  # Tailwind green-500
  defp hex_color("yellow"), do: "#eab308" # Tailwind yellow-500
  defp hex_color("black"), do: "#1f2937"  # Tailwind gray-800
  defp hex_color(_), do: "#9ca3af"        # Fallback

  # Maps logical state values to display characters
  defp display_value("skip"), do: "⊘"
  defp display_value("reverse"), do: "⇄"
  defp display_value("draw2"), do: "+2"
  defp display_value("wild"), do: "W"
  defp display_value("wild_draw4"), do: "+4"
  defp display_value(val), do: val

  # Scales the center text dynamically so "+4" fits inside the oval
  defp center_font_size(val) when val in ["draw2", "wild_draw4"], do: "42"
  defp center_font_size("reverse"), do: "56"
  defp center_font_size(_), do: "64"
end
