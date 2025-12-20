defmodule BezgelorDev.StubGenerator do
  @moduledoc """
  Generates stub code for new packets and handlers.

  Creates Elixir module files based on Claude's analysis or manual input,
  following Bezgelor's code conventions.
  """

  @doc """
  Generates an opcode entry to add to Opcode.ex.
  """
  @spec generate_opcode_entry(integer(), String.t()) :: String.t()
  def generate_opcode_entry(opcode_int, suggested_name) do
    atom_name = to_atom_name(suggested_name)

    hex_value =
      "0x#{Integer.to_string(opcode_int, 16) |> String.upcase() |> String.pad_leading(4, "0")}"

    """
    # Add to module attributes section:
    @#{atom_name} #{hex_value}

    # Add to @opcode_map:
    #{atom_name}: @#{atom_name},

    # Add to @names:
    #{atom_name}: "#{suggested_name}",
    """
  end

  @doc """
  Generates a packet struct module.
  """
  @spec generate_packet_struct(String.t(), integer(), list()) :: String.t()
  def generate_packet_struct(suggested_name, opcode_int, field_analysis) do
    _atom_name = to_atom_name(suggested_name)
    module_name = determine_module_path(suggested_name, opcode_int)
    fields = generate_struct_fields(field_analysis)
    field_names = extract_field_names(field_analysis)
    read_impl = generate_read_implementation(field_analysis)

    """
    defmodule #{module_name} do
      @moduledoc \"\"\"
      #{suggested_name} packet.

      Opcode: 0x#{Integer.to_string(opcode_int, 16) |> String.upcase() |> String.pad_leading(4, "0")}

      ## Fields
      #{format_fields_doc(field_analysis)}

      ---
      Auto-generated stub - needs verification and testing.
      \"\"\"

      alias BezgelorProtocol.PacketReader

      defstruct #{inspect(field_names)}

      @type t :: %__MODULE__{
    #{fields}
            }

      @behaviour BezgelorProtocol.Readable

      @impl true
      def read(reader) do
    #{read_impl}
      end
    end
    """
  end

  @doc """
  Generates a handler stub module.
  """
  @spec generate_handler_stub(String.t(), integer()) :: String.t()
  def generate_handler_stub(suggested_name, opcode_int) do
    handler_name = derive_handler_name(suggested_name)
    atom_name = to_atom_name(suggested_name)
    packet_module = determine_module_path(suggested_name, opcode_int)

    """
    defmodule BezgelorProtocol.Handler.#{handler_name} do
      @moduledoc \"\"\"
      Handler for #{suggested_name}.

      Processes :#{atom_name} packets from clients.

      ---
      Auto-generated stub - needs implementation.
      \"\"\"

      @behaviour BezgelorProtocol.Handler

      require Logger

      alias BezgelorProtocol.PacketReader
      alias #{packet_module}

      @impl true
      def handle(payload, state) do
        reader = PacketReader.new(payload)

        case #{String.split(packet_module, ".") |> List.last()}.read(reader) do
          {:ok, packet} ->
            Logger.debug("Received #{suggested_name}: \#{inspect(packet)}")

            # TODO: Implement packet handling logic
            # Example patterns:
            # - Update player state
            # - Broadcast to other players
            # - Query database
            # - Send response packet

            {:ok, state}

          {:error, reason} ->
            Logger.warning("Failed to parse #{suggested_name}: \#{inspect(reason)}")
            {:ok, state}
        end
      end
    end
    """
  end

  @doc """
  Generates a test stub for a packet.
  """
  @spec generate_test_stub(String.t(), integer(), binary()) :: String.t()
  def generate_test_stub(suggested_name, opcode_int, sample_payload) do
    atom_name = to_atom_name(suggested_name)
    module_name = determine_module_path(suggested_name, opcode_int)
    test_module_name = "#{module_name}Test"
    hex_payload = Base.encode16(sample_payload, case: :lower)

    """
    defmodule #{test_module_name} do
      use ExUnit.Case, async: true

      alias BezgelorProtocol.PacketReader
      alias #{module_name}

      describe "read/1" do
        test "parses #{atom_name} packet" do
          # Sample payload captured during gameplay
          payload = Base.decode16!("#{hex_payload}")
          reader = PacketReader.new(payload)

          assert {:ok, packet} = #{String.split(module_name, ".") |> List.last()}.read(reader)

          # TODO: Add assertions for expected field values
          # assert packet.field_name == expected_value
        end
      end
    end
    """
  end

  @doc """
  Writes generated stubs to files in the capture session directory.
  """
  @spec write_stubs_to_session(String.t(), String.t(), map()) ::
          {:ok, [String.t()]} | {:error, term()}
  def write_stubs_to_session(session_id, suggested_name, analysis) do
    base_dir = BezgelorDev.capture_directory()
    stubs_dir = Path.join([base_dir, "sessions", session_id, "generated_stubs"])
    File.mkdir_p!(stubs_dir)

    atom_name = to_atom_name(suggested_name)
    opcode_int = analysis["opcode"] || 0
    field_analysis = analysis["field_analysis"] || []

    files_written = []

    # Write opcode entry
    opcode_path = Path.join(stubs_dir, "#{atom_name}_opcode.txt")
    File.write!(opcode_path, generate_opcode_entry(opcode_int, suggested_name))
    files_written = [opcode_path | files_written]

    # Write packet struct
    packet_path = Path.join(stubs_dir, "#{atom_name}.ex")
    File.write!(packet_path, generate_packet_struct(suggested_name, opcode_int, field_analysis))
    files_written = [packet_path | files_written]

    # Write handler
    handler_name = derive_handler_name(suggested_name) |> Macro.underscore()
    handler_path = Path.join(stubs_dir, "#{handler_name}.ex")
    File.write!(handler_path, generate_handler_stub(suggested_name, opcode_int))
    files_written = [handler_path | files_written]

    {:ok, Enum.reverse(files_written)}
  end

  # Private helpers

  defp to_atom_name(suggested_name) do
    suggested_name
    |> Macro.underscore()
    |> String.to_atom()
    |> Atom.to_string()
  end

  defp derive_handler_name(suggested_name) do
    suggested_name
    |> String.replace(~r/^Client/, "")
    |> String.replace(~r/^Server/, "")
    |> Kernel.<>("Handler")
  end

  defp determine_module_path(suggested_name, _opcode_int) do
    # Determine if this is a world, realm, or auth packet based on name patterns
    cond do
      String.starts_with?(suggested_name, "ClientAuth") or
          String.starts_with?(suggested_name, "ServerAuth") ->
        "BezgelorProtocol.Packets.#{suggested_name}"

      String.starts_with?(suggested_name, "ClientRealm") or
          String.starts_with?(suggested_name, "ServerRealm") ->
        "BezgelorProtocol.Packets.Realm.#{suggested_name}"

      true ->
        "BezgelorProtocol.Packets.World.#{suggested_name}"
    end
  end

  defp generate_struct_fields(field_analysis) do
    field_analysis
    |> Enum.map(fn field ->
      name = field["likely_meaning"] || "field_#{field["offset"]}"
      type = elixir_type_from_analysis(field["type"])
      "        #{name}: #{type}"
    end)
    |> Enum.join(",\n")
  end

  defp extract_field_names(field_analysis) do
    field_analysis
    |> Enum.map(fn field ->
      name = field["likely_meaning"] || "field_#{field["offset"]}"
      String.to_atom(name)
    end)
  end

  defp elixir_type_from_analysis("uint8"), do: "non_neg_integer()"
  defp elixir_type_from_analysis("uint16"), do: "non_neg_integer()"
  defp elixir_type_from_analysis("uint32"), do: "non_neg_integer()"
  defp elixir_type_from_analysis("uint64"), do: "non_neg_integer()"
  defp elixir_type_from_analysis("int8"), do: "integer()"
  defp elixir_type_from_analysis("int16"), do: "integer()"
  defp elixir_type_from_analysis("int32"), do: "integer()"
  defp elixir_type_from_analysis("int64"), do: "integer()"
  defp elixir_type_from_analysis("float32"), do: "float()"
  defp elixir_type_from_analysis("float64"), do: "float()"
  defp elixir_type_from_analysis("string"), do: "String.t()"
  defp elixir_type_from_analysis("bool"), do: "boolean()"
  defp elixir_type_from_analysis("guid"), do: "non_neg_integer()"
  defp elixir_type_from_analysis(_), do: "term()"

  defp generate_read_implementation(field_analysis) do
    if Enum.empty?(field_analysis) do
      """
          # TODO: Implement packet parsing based on actual packet structure
          {:ok, %__MODULE__{}}
      """
    else
      reads = generate_field_reads(field_analysis)
      struct_build = generate_struct_build(field_analysis)

      """
      #{reads}

          {:ok, %__MODULE__{#{struct_build}}}
      """
    end
  end

  defp generate_field_reads(field_analysis) do
    field_analysis
    |> Enum.map(fn field ->
      name = field["likely_meaning"] || "field_#{field["offset"]}"
      read_fn = read_function_for_type(field["type"])
      "    {#{name}, reader} = PacketReader.#{read_fn}(reader)"
    end)
    |> Enum.join("\n")
  end

  defp generate_struct_build(field_analysis) do
    field_analysis
    |> Enum.map(fn field ->
      name = field["likely_meaning"] || "field_#{field["offset"]}"
      "#{name}: #{name}"
    end)
    |> Enum.join(", ")
  end

  defp read_function_for_type("uint8"), do: "read_uint8"
  defp read_function_for_type("uint16"), do: "read_uint16"
  defp read_function_for_type("uint32"), do: "read_uint32"
  defp read_function_for_type("uint64"), do: "read_uint64"
  defp read_function_for_type("int8"), do: "read_int8"
  defp read_function_for_type("int16"), do: "read_int16"
  defp read_function_for_type("int32"), do: "read_int32"
  defp read_function_for_type("int64"), do: "read_int64"
  defp read_function_for_type("float32"), do: "read_float32"
  defp read_function_for_type("float64"), do: "read_float64"
  defp read_function_for_type("string"), do: "read_wide_string"
  defp read_function_for_type("bool"), do: "read_bool"
  defp read_function_for_type("guid"), do: "read_uint64"
  defp read_function_for_type(_), do: "read_uint32"

  defp format_fields_doc([]), do: "_No fields analyzed_"

  defp format_fields_doc(field_analysis) do
    field_analysis
    |> Enum.map(fn field ->
      offset = field["offset"] || 0
      size = field["size"] || 0
      type = field["type"] || "unknown"
      meaning = field["likely_meaning"] || "unknown"
      "  - `#{meaning}` (#{type}) - offset #{offset}, #{size} bytes"
    end)
    |> Enum.join("\n")
  end
end
