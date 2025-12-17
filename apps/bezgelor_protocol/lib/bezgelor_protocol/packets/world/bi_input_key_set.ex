defmodule BezgelorProtocol.Packets.World.BiInputKeySet do
  @moduledoc """
  Bidirectional keybinding data packet.

  Contains a list of keybindings for the account or character.
  Sent in response to ClientRequestInputKeySet.

  ## Wire Format
  bindings_count : uint32
  bindings[]     : Binding struct (complex)
  character_id   : uint64

  ## Binding struct (each ~50 bytes)
  input_action_id : 14 bits
  device_enum_00  : uint32
  device_enum_01  : uint32
  device_enum_02  : uint32
  code_00         : uint32
  code_01         : uint32
  code_02         : uint32
  meta_keys_00    : uint32
  meta_keys_01    : uint32
  meta_keys_02    : uint32
  event_type_00   : uint32
  event_type_01   : uint32
  event_type_02   : uint32
  """

  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct bindings: [],
            character_id: 0

  @type binding :: %{
          input_action_id: non_neg_integer(),
          device_enum_00: non_neg_integer(),
          device_enum_01: non_neg_integer(),
          device_enum_02: non_neg_integer(),
          code_00: non_neg_integer(),
          code_01: non_neg_integer(),
          code_02: non_neg_integer(),
          meta_keys_00: non_neg_integer(),
          meta_keys_01: non_neg_integer(),
          meta_keys_02: non_neg_integer(),
          event_type_00: non_neg_integer(),
          event_type_01: non_neg_integer(),
          event_type_02: non_neg_integer()
        }

  @type t :: %__MODULE__{
          bindings: [binding()],
          character_id: non_neg_integer()
        }

  @impl true
  def opcode, do: :bi_input_key_set

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    writer =
      writer
      |> PacketWriter.write_u32(length(packet.bindings))
      |> write_bindings(packet.bindings)
      |> PacketWriter.write_u64(packet.character_id)

    {:ok, writer}
  end

  defp write_bindings(writer, []), do: writer

  defp write_bindings(writer, [binding | rest]) do
    writer
    |> PacketWriter.write_bits(binding.input_action_id, 14)
    |> PacketWriter.write_u32(binding.device_enum_00)
    |> PacketWriter.write_u32(binding.device_enum_01)
    |> PacketWriter.write_u32(binding.device_enum_02)
    |> PacketWriter.write_u32(binding.code_00)
    |> PacketWriter.write_u32(binding.code_01)
    |> PacketWriter.write_u32(binding.code_02)
    |> PacketWriter.write_u32(binding.meta_keys_00)
    |> PacketWriter.write_u32(binding.meta_keys_01)
    |> PacketWriter.write_u32(binding.meta_keys_02)
    |> PacketWriter.write_u32(binding.event_type_00)
    |> PacketWriter.write_u32(binding.event_type_01)
    |> PacketWriter.write_u32(binding.event_type_02)
    |> write_bindings(rest)
  end
end
