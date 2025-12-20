defmodule BezgelorDev.LlmAssistant do
  @compile {:no_warn_undefined, BezgelorProtocol.Opcode}
  @moduledoc """
  Generates LLM-ready prompts for packet analysis.

  Instead of calling an LLM API directly during gameplay, this module
  generates rich, structured prompts that can be fed into an LLM
  for offline analysis. This approach:

  1. Doesn't interrupt gameplay flow
  2. Allows batch analysis of multiple packets
  3. Gives you full control over when/how to analyze
  4. Works without API key configuration

  ## Usage

  After a gameplay session, export the captures and feed them to your LLM:

      # In IEx
      BezgelorDev.DevCapture.export_captures(:markdown)

      # Or generate prompts directly:
      BezgelorDev.LlmAssistant.save_prompts_for_analysis(session_id, events)

      # Then in your LLM:
      "Analyze the packet capture in priv/dev_captures/sessions/..."
  """

  @doc """
  Generates a Claude Code prompt for analyzing a captured packet.

  Returns a prompt string that can be copied into Claude Code for analysis.
  """
  @spec generate_analysis_prompt(map()) :: String.t()
  def generate_analysis_prompt(event) do
    context = event.context
    recent_packets = format_recent_packets(context.recent_packets)

    """
    # WildStar Packet Analysis Request

    I'm working on Bezgelor, an Elixir WildStar server emulator (port of NexusForever).
    I captured an unknown packet during gameplay and need help analyzing it.

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

    ## Capture Context

    ### Player State
    - **Zone**: #{context.player_zone_name || context.player_zone_id || "Unknown"}
    - **Position**: #{format_position(context.player_position)}
    - **Player**: #{context.player_name || "Unknown"}
    - **In World**: #{context.in_world}
    - **Session State**: #{context.session_state}

    ### Recent Packets (before this one)
    #{recent_packets}

    ### What I Was Doing
    #{format_commentary(event.player_commentary)}

    ## What I Need

    1. **Suggest an opcode name** following WildStar/NexusForever conventions
       (e.g., ClientInventoryMove, ClientQuestAccept)

    2. **Analyze the byte structure** - identify likely fields:
       - Data types (uint32, uint16, uint8, float32, string, etc.)
       - Offsets and sizes
       - Likely meanings based on context

    3. **Generate Elixir code** for:
       - Opcode entry for `apps/bezgelor_protocol/lib/bezgelor_protocol/opcode.ex`
       - Packet struct module with `Readable` behaviour
       - Handler stub module

    4. **Reference NexusForever** if you can find similar patterns in the C# codebase

    ## Codebase Context

    The project structure is:
    - `apps/bezgelor_protocol/lib/bezgelor_protocol/opcode.ex` - Opcode definitions
    - `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/` - Packet structs
    - `apps/bezgelor_protocol/lib/bezgelor_protocol/handler/` - Packet handlers
    - `apps/bezgelor_protocol/lib/bezgelor_protocol/packet_reader.ex` - Binary parsing

    Packets implement `BezgelorProtocol.Readable` with a `read/1` function.
    Handlers implement `BezgelorProtocol.Handler` with a `handle/2` function.
    """
  end

  @doc """
  Generates a batch analysis prompt for multiple captures.
  """
  @spec generate_batch_prompt([map()]) :: String.t()
  def generate_batch_prompt(events) do
    individual_packets =
      events
      |> Enum.with_index(1)
      |> Enum.map(fn {event, idx} ->
        """
        ---

        ## Packet #{idx}: #{event.opcode_hex}

        - **Size**: #{byte_size(event.payload)} bytes
        - **Raw hex**: #{Base.encode16(event.payload, case: :lower)}
        - **Context**: #{format_brief_context(event)}
        - **Player was**: #{event.player_commentary || "No description"}
        """
      end)
      |> Enum.join("\n")

    """
    # Batch WildStar Packet Analysis

    I'm working on Bezgelor, an Elixir WildStar server emulator.
    I captured #{length(events)} unknown packets during a gameplay session.

    Please analyze each packet and suggest:
    1. Opcode names
    2. Field structures
    3. Implementation priorities (which to implement first based on importance)

    #{individual_packets}

    ---

    ## Summary Request

    After analyzing each packet, please provide:
    1. A summary table of all packets with suggested names
    2. Recommended implementation order
    3. Any patterns you notice (related packets, common structures)
    """
  end

  @doc """
  Saves analysis prompts to a file for easy copying to Claude Code.
  """
  @spec save_prompts_for_analysis(String.t(), [map()]) :: {:ok, String.t()} | {:error, term()}
  def save_prompts_for_analysis(session_id, events) do
    base_dir = BezgelorDev.capture_directory()
    session_dir = Path.join([base_dir, "sessions", session_id])

    # Save individual prompts
    prompts_dir = Path.join(session_dir, "analysis_prompts")
    File.mkdir_p!(prompts_dir)

    Enum.each(events, fn event ->
      filename = "prompt_#{event.opcode_hex |> String.replace("0x", "")}.md"
      path = Path.join(prompts_dir, filename)
      prompt = generate_analysis_prompt(event)
      File.write!(path, prompt)
    end)

    # Save batch prompt
    if length(events) > 1 do
      batch_path = Path.join(prompts_dir, "batch_analysis.md")
      batch_prompt = generate_batch_prompt(events)
      File.write!(batch_path, batch_prompt)
    end

    {:ok, prompts_dir}
  end

  # Private helpers

  defp format_decimal(opcode) when is_integer(opcode), do: Integer.to_string(opcode)

  defp format_decimal(opcode) when is_atom(opcode) do
    try do
      Integer.to_string(BezgelorProtocol.Opcode.to_integer(opcode))
    rescue
      _ -> Atom.to_string(opcode)
    end
  end

  defp format_position(nil), do: "Unknown"

  defp format_position({x, y, z}) do
    "(#{Float.round(x * 1.0, 1)}, #{Float.round(y * 1.0, 1)}, #{Float.round(z * 1.0, 1)})"
  end

  defp format_recent_packets([]), do: "_No recent packets recorded_"

  defp format_recent_packets(packets) do
    packets
    |> Enum.take(10)
    |> Enum.map(fn p ->
      direction = if p.direction == :inbound, do: "←", else: "→"
      "| #{direction} | #{p.opcode_name} | #{p.time_ago_ms}ms |"
    end)
    |> then(fn rows ->
      "| Dir | Opcode | Time Ago |\n|-----|--------|----------|\n" <> Enum.join(rows, "\n")
    end)
  end

  defp format_commentary(nil), do: "_No description provided during capture_"
  defp format_commentary(""), do: "_No description provided during capture_"
  defp format_commentary(text), do: "> #{text}"

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

  defp format_brief_context(event) do
    ctx = event.context
    zone = ctx.player_zone_name || ctx.player_zone_id || "?"
    "Zone: #{zone}, State: #{ctx.session_state}"
  end
end
