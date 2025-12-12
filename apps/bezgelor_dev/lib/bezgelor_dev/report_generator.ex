defmodule BezgelorDev.ReportGenerator do
  @moduledoc """
  Generates markdown and JSON reports for captured packets.

  Reports include all captured context, player commentary, and
  any Claude analysis results for later reference.
  """

  alias BezgelorDev.PacketContext

  @doc """
  Generates a markdown report for a single capture event.
  """
  @spec generate_markdown_report(map()) :: String.t()
  def generate_markdown_report(event) do
    """
    # #{capture_type_title(event.type)}: #{event.opcode_hex}

    ## Capture Details
    - **Timestamp**: #{DateTime.to_iso8601(event.timestamp)}
    - **Type**: #{event.type}
    - **Connection**: #{event.context.connection_type}
    #{if event.context.player_name, do: "- **Player**: #{event.context.player_name}", else: ""}

    ## Packet Data
    - **Opcode**: #{event.opcode_hex} (#{format_decimal(event.opcode)} decimal)
    - **Size**: #{byte_size(event.payload)} bytes
    - **Direction**: Client → Server

    ### Raw Bytes (hex)
    ```
    #{format_hex_dump(event.payload)}
    ```

    ### Raw Bytes (base64)
    ```
    #{Base.encode64(event.payload)}
    ```

    #{format_error_section(event.error)}

    ## Context

    ### Player State
    #{format_player_state(event.context)}

    ### Recent Packets
    #{format_recent_packets_table(event.context.recent_packets)}

    ## Player Description
    #{format_player_commentary(event.player_commentary)}

    #{format_claude_analysis(event.claude_analysis)}
    """
    |> String.trim()
  end

  @doc """
  Generates a JSON report for a single capture event.
  """
  @spec generate_json_report(map()) :: String.t()
  def generate_json_report(event) do
    %{
      type: event.type,
      timestamp: DateTime.to_iso8601(event.timestamp),
      opcode: %{
        value: event.opcode,
        hex: event.opcode_hex,
        decimal: format_decimal(event.opcode)
      },
      payload: %{
        size: byte_size(event.payload),
        hex: event.payload_hex,
        base64: Base.encode64(event.payload)
      },
      error: if(event.error, do: inspect(event.error), else: nil),
      context: PacketContext.to_map(event.context),
      player_commentary: event.player_commentary,
      claude_analysis: event.claude_analysis
    }
    |> Jason.encode!(pretty: true)
  end

  @doc """
  Generates a summary report for multiple captures.
  """
  @spec generate_summary_report([map()], map()) :: String.t()
  def generate_summary_report(captures, state) do
    by_type = Enum.group_by(captures, & &1.type)

    """
    # Development Capture Summary

    ## Session Information
    - **Session ID**: #{state.session_id}
    - **Started**: #{DateTime.to_iso8601(state.session_start)}
    - **Total Captures**: #{length(captures)}

    ## Captures by Type

    | Type | Count |
    |------|-------|
    #{format_type_counts(by_type)}

    ## Unknown Opcodes
    #{format_unknown_opcodes_list(Map.get(by_type, :unknown_opcode, []))}

    ## Unhandled Opcodes
    #{format_unhandled_opcodes_list(Map.get(by_type, :unhandled_opcode, []))}

    ## Handler Errors
    #{format_handler_errors_list(Map.get(by_type, :handler_error, []))}

    ## All Captures (Chronological)
    #{format_captures_table(captures)}
    """
    |> String.trim()
  end

  # Private formatting functions

  defp capture_type_title(:unknown_opcode), do: "Unknown Packet Report"
  defp capture_type_title(:unhandled_opcode), do: "Unhandled Packet Report"
  defp capture_type_title(:handler_error), do: "Handler Error Report"

  defp format_decimal(opcode) when is_integer(opcode), do: Integer.to_string(opcode)
  defp format_decimal(opcode) when is_atom(opcode) do
    try do
      Integer.to_string(BezgelorProtocol.Opcode.to_integer(opcode))
    rescue
      _ -> Atom.to_string(opcode)
    end
  end

  defp format_hex_dump(binary) do
    binary
    |> :binary.bin_to_list()
    |> Enum.chunk_every(16)
    |> Enum.with_index()
    |> Enum.map(fn {chunk, idx} ->
      offset = String.pad_leading(Integer.to_string(idx * 16, 16), 8, "0")

      hex_part =
        chunk
        |> Enum.map(&String.pad_leading(Integer.to_string(&1, 16), 2, "0"))
        |> Enum.chunk_every(8)
        |> Enum.map(&Enum.join(&1, " "))
        |> Enum.join("  ")
        |> String.pad_trailing(49)

      ascii_part =
        chunk
        |> Enum.map(fn byte ->
          if byte >= 32 and byte < 127, do: <<byte>>, else: "."
        end)
        |> Enum.join()

      "#{offset}  #{hex_part}  |#{ascii_part}|"
    end)
    |> Enum.join("\n")
  end

  defp format_error_section(nil), do: ""
  defp format_error_section(error) do
    """
    ## Error Details
    ```
    #{inspect(error, pretty: true)}
    ```
    """
  end

  defp format_player_state(context) do
    items = [
      if(context.player_name, do: "- **Name**: #{context.player_name}"),
      if(context.player_id, do: "- **ID**: #{context.player_id}"),
      if(context.player_zone_name || context.player_zone_id,
        do: "- **Zone**: #{context.player_zone_name || context.player_zone_id}"),
      if(context.player_position, do: "- **Position**: #{format_position(context.player_position)}"),
      "- **Session State**: #{context.session_state}",
      "- **In World**: #{context.in_world}"
    ]

    items
    |> Enum.filter(& &1)
    |> Enum.join("\n")
  end

  defp format_position(nil), do: "Unknown"
  defp format_position({x, y, z}) do
    "(#{Float.round(x * 1.0, 2)}, #{Float.round(y * 1.0, 2)}, #{Float.round(z * 1.0, 2)})"
  end

  defp format_recent_packets_table([]), do: "_No recent packets recorded_"
  defp format_recent_packets_table(packets) do
    header = "| Direction | Opcode | Time Ago |\n|-----------|--------|----------|\n"

    rows =
      packets
      |> Enum.take(10)
      |> Enum.map(fn packet ->
        direction = if packet.direction == :inbound, do: "C→S", else: "S→C"
        time_ago = format_time_ago(packet.time_ago_ms)
        "| #{direction} | #{packet.opcode_name} | #{time_ago} |"
      end)
      |> Enum.join("\n")

    header <> rows
  end

  defp format_time_ago(ms) when ms < 1000, do: "#{ms}ms"
  defp format_time_ago(ms) when ms < 60_000, do: "#{Float.round(ms / 1000, 1)}s"
  defp format_time_ago(ms), do: "#{Float.round(ms / 60_000, 1)}m"

  defp format_player_commentary(nil), do: "> _No description provided_"
  defp format_player_commentary(""), do: "> _No description provided_"
  defp format_player_commentary(commentary), do: "> \"#{commentary}\""

  defp format_claude_analysis(nil), do: ""
  defp format_claude_analysis(analysis) do
    """
    ## Claude Analysis

    ### Suggested Name
    **#{analysis["suggested_name"] || "Unknown"}** (Confidence: #{analysis["confidence"] || "unknown"})

    ### Reasoning
    #{analysis["reasoning"] || "_No reasoning provided_"}

    ### Field Analysis
    #{format_field_analysis(analysis["field_analysis"])}

    #{if analysis["nexusforever_reference"], do: "### NexusForever Reference\n#{analysis["nexusforever_reference"]}", else: ""}
    """
  end

  defp format_field_analysis(nil), do: "_No field analysis available_"
  defp format_field_analysis([]), do: "_No field analysis available_"
  defp format_field_analysis(fields) do
    header = "| Offset | Size | Type | Meaning |\n|--------|------|------|--------|\n"

    rows =
      fields
      |> Enum.map(fn field ->
        offset = field["offset"] || 0
        size = field["size"] || 0
        type = field["type"] || "unknown"
        meaning = field["likely_meaning"] || "unknown"
        "| #{offset} | #{size} | #{type} | #{meaning} |"
      end)
      |> Enum.join("\n")

    header <> rows
  end

  defp format_type_counts(by_type) do
    [
      {:unknown_opcode, "Unknown Opcode"},
      {:unhandled_opcode, "Unhandled Opcode"},
      {:handler_error, "Handler Error"}
    ]
    |> Enum.map(fn {type, label} ->
      count = length(Map.get(by_type, type, []))
      "| #{label} | #{count} |"
    end)
    |> Enum.join("\n")
  end

  defp format_unknown_opcodes_list([]), do: "_None captured_"
  defp format_unknown_opcodes_list(captures) do
    captures
    |> Enum.uniq_by(& &1.opcode)
    |> Enum.map(fn c -> "- #{c.opcode_hex}" end)
    |> Enum.join("\n")
  end

  defp format_unhandled_opcodes_list([]), do: "_None captured_"
  defp format_unhandled_opcodes_list(captures) do
    captures
    |> Enum.uniq_by(& &1.opcode)
    |> Enum.map(fn c ->
      name = if is_atom(c.opcode), do: Atom.to_string(c.opcode), else: c.opcode_hex
      "- #{name} (#{c.opcode_hex})"
    end)
    |> Enum.join("\n")
  end

  defp format_handler_errors_list([]), do: "_None captured_"
  defp format_handler_errors_list(captures) do
    captures
    |> Enum.map(fn c ->
      name = if is_atom(c.opcode), do: Atom.to_string(c.opcode), else: c.opcode_hex
      "- #{name}: #{inspect(c.error)}"
    end)
    |> Enum.join("\n")
  end

  defp format_captures_table(captures) do
    header = "| # | Time | Type | Opcode | Commentary |\n|---|------|------|--------|------------|\n"

    rows =
      captures
      |> Enum.reverse()
      |> Enum.with_index(1)
      |> Enum.map(fn {c, idx} ->
        time = Calendar.strftime(c.timestamp, "%H:%M:%S")
        type = capture_type_short(c.type)
        opcode = c.opcode_hex
        commentary = truncate(c.player_commentary || "-", 30)
        "| #{idx} | #{time} | #{type} | #{opcode} | #{commentary} |"
      end)
      |> Enum.join("\n")

    header <> rows
  end

  defp capture_type_short(:unknown_opcode), do: "Unknown"
  defp capture_type_short(:unhandled_opcode), do: "Unhandled"
  defp capture_type_short(:handler_error), do: "Error"

  defp truncate(nil, _max), do: "-"
  defp truncate(str, max) when byte_size(str) <= max, do: str
  defp truncate(str, max), do: String.slice(str, 0, max - 3) <> "..."
end
