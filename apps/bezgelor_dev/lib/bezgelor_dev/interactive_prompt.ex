defmodule BezgelorDev.InteractivePrompt do
  @compile {:no_warn_undefined, BezgelorProtocol.Opcode}
  @moduledoc """
  Interactive terminal UI for capturing player context.

  When an unknown packet is captured in interactive mode, this module
  displays packet information and prompts the player for what they
  were doing, enabling better reverse engineering analysis.

  The captured context is saved to rich log files that can later be
  fed into Claude Code for analysis.
  """

  @doc """
  Prompts for context when a capture event occurs.

  Returns `{commentary, action}` where:
  - `commentary` is the player's description of what they were doing
  - `action` is one of `:log`, `:skip`, or `:quit`
  """
  @spec prompt_for_context(map()) :: {String.t() | nil, atom()}
  def prompt_for_context(event) do
    display_capture_header(event)
    display_packet_data(event)
    display_recent_context(event)

    commentary = prompt_player_commentary()
    action = prompt_action_menu()

    {commentary, action}
  end

  @doc """
  Displays a summary after saving a capture.
  """
  @spec display_save_confirmation(String.t()) :: :ok
  def display_save_confirmation(path) do
    IO.puts(color("\n  Saved to: #{path}", :green))
    IO.puts(color("  Feed this to Claude Code later for analysis.", :cyan))
    IO.puts("")
  end

  # Private functions

  defp display_capture_header(event) do
    type_label = capture_type_label(event.type)
    type_color = capture_type_color(event.type)

    IO.puts(
      color("\n═══════════════════════════════════════════════════════════════", type_color)
    )

    IO.puts(color("  #{type_label} DETECTED", type_color))
    IO.puts(color("═══════════════════════════════════════════════════════════════", type_color))
  end

  defp display_packet_data(event) do
    IO.puts(
      "\n  #{color("Opcode:", :yellow)} #{event.opcode_hex} (#{format_opcode_decimal(event.opcode)} decimal)"
    )

    IO.puts("  #{color("Size:", :yellow)} #{byte_size(event.payload)} bytes")

    # Display raw bytes (first 48 bytes max)
    raw_display = format_hex_preview(event.payload, 48)
    IO.puts("  #{color("Raw:", :yellow)} #{raw_display}")

    if event.error do
      IO.puts("  #{color("Error:", :red)} #{inspect(event.error)}")
    end
  end

  defp display_recent_context(event) do
    context = event.context

    IO.puts("\n  #{color("Recent context:", :cyan)}")

    # Recent packets
    recent = Enum.take(context.recent_packets, 5)

    if length(recent) > 0 do
      Enum.each(recent, fn packet ->
        direction_symbol = if packet.direction == :inbound, do: "←", else: "→"
        time_ago = format_time_ago(packet.time_ago_ms)

        IO.puts("  • #{direction_symbol} #{packet.opcode_name} (#{time_ago})")
      end)
    else
      IO.puts("  • No recent packets recorded")
    end

    # Player state
    if context.player_zone_name || context.player_zone_id do
      zone = context.player_zone_name || "Zone #{context.player_zone_id}"
      IO.puts("  • #{color("Zone:", :yellow)} #{zone}")
    end

    if context.player_position do
      {x, y, z} = context.player_position

      IO.puts(
        "  • #{color("Position:", :yellow)} (#{Float.round(x, 1)}, #{Float.round(y, 1)}, #{Float.round(z, 1)})"
      )
    end

    if context.player_name do
      IO.puts("  • #{color("Player:", :yellow)} #{context.player_name}")
    end
  end

  defp prompt_player_commentary do
    IO.puts(color("\n───────────────────────────────────────────────────────────────", :white))
    IO.puts("  What were you doing when this happened?")
    IO.puts("  (Press Enter to skip)")

    case IO.gets("  > ") do
      :eof ->
        nil

      {:error, _} ->
        nil

      input ->
        commentary = String.trim(input)
        if commentary == "", do: nil, else: commentary
    end
  end

  defp prompt_action_menu do
    IO.puts(color("───────────────────────────────────────────────────────────────", :white))

    IO.puts(
      "  [#{color("L", :blue)}]og for Analysis  [#{color("S", :yellow)}]kip  [#{color("Q", :red)}]uit dev mode"
    )

    case IO.gets("  > ") do
      :eof ->
        :skip

      {:error, _} ->
        :skip

      input ->
        case String.trim(input) |> String.downcase() do
          "l" -> :log
          "s" -> :skip
          "q" -> :quit
          # Default to log
          "" -> :log
          _ -> :log
        end
    end
  end

  # Formatting helpers

  defp capture_type_label(:unknown_opcode), do: "UNKNOWN PACKET"
  defp capture_type_label(:unhandled_opcode), do: "UNHANDLED PACKET"
  defp capture_type_label(:handler_error), do: "HANDLER ERROR"

  defp capture_type_color(:unknown_opcode), do: :red
  defp capture_type_color(:unhandled_opcode), do: :yellow
  defp capture_type_color(:handler_error), do: :magenta

  defp format_opcode_decimal(opcode) when is_integer(opcode), do: Integer.to_string(opcode)

  defp format_opcode_decimal(opcode) when is_atom(opcode) do
    try do
      Integer.to_string(BezgelorProtocol.Opcode.to_integer(opcode))
    rescue
      _ -> Atom.to_string(opcode)
    end
  end

  defp format_hex_preview(binary, max_bytes) do
    bytes = binary_part(binary, 0, min(byte_size(binary), max_bytes))
    hex = Base.encode16(bytes, case: :lower)

    # Format in groups of 2 (bytes)
    formatted =
      hex
      |> String.graphemes()
      |> Enum.chunk_every(2)
      |> Enum.map(&Enum.join/1)
      |> Enum.join(" ")

    if byte_size(binary) > max_bytes do
      formatted <> "..."
    else
      formatted
    end
  end

  defp format_time_ago(ms) when ms < 1000, do: "#{ms}ms ago"

  defp format_time_ago(ms) when ms < 60_000 do
    seconds = div(ms, 1000)
    "#{seconds}s ago"
  end

  defp format_time_ago(ms) do
    minutes = div(ms, 60_000)
    "#{minutes}m ago"
  end

  defp color(text, color_name) do
    # Use IO.ANSI for colored output
    ansi_code = apply(IO.ANSI, color_name, [])
    reset = IO.ANSI.reset()
    "#{ansi_code}#{text}#{reset}"
  end
end
