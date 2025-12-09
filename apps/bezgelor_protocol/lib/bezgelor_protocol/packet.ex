defmodule BezgelorProtocol.Packet do
  @moduledoc """
  Base packet types and behaviours for WildStar protocol.

  ## Packet Structure

  All WildStar packets have a 6-byte header:

      ┌──────────────┬──────────────┐
      │ Size (4 bytes)│ Opcode (2 bytes)│
      └──────────────┴──────────────┘

  - Size is little-endian uint32, includes the size field itself
  - Opcode is little-endian uint16

  ## Behaviours

  Packets implement either `Readable` (for parsing) or `Writable` (for
  serialization), or both:

      defmodule MyPacket do
        @behaviour BezgelorProtocol.Packet.Readable
        @behaviour BezgelorProtocol.Packet.Writable

        defstruct [:field1, :field2]

        @impl true
        def read(reader) do
          # Parse from reader
        end

        @impl true
        def write(packet, writer) do
          # Serialize to writer
        end

        @impl true
        def opcode, do: :my_packet_opcode
      end
  """

  @header_size 6

  @doc "Returns the header size in bytes (always 6)."
  @spec header_size() :: 6
  def header_size, do: @header_size

  @doc """
  Parse a packet header from binary.

  Returns `{:ok, size, opcode}` or `{:error, :incomplete}`.
  """
  @spec parse_header(binary()) :: {:ok, non_neg_integer(), non_neg_integer()} | {:error, :incomplete}
  def parse_header(<<size::little-32, opcode::little-16>>) do
    {:ok, size, opcode}
  end

  def parse_header(_), do: {:error, :incomplete}

  @doc """
  Build a packet header from size and opcode.
  """
  @spec build_header(non_neg_integer(), non_neg_integer()) :: binary()
  def build_header(size, opcode) do
    <<size::little-32, opcode::little-16>>
  end

  @doc """
  Calculate size field value from payload size.

  The size field includes itself (4 bytes) but not the opcode (2 bytes).
  Size field value = 4 + payload
  """
  @spec packet_size(non_neg_integer()) :: non_neg_integer()
  def packet_size(payload_size), do: 4 + payload_size

  @doc """
  Calculate payload size from the size field value.
  """
  @spec payload_size(non_neg_integer()) :: non_neg_integer()
  def payload_size(size_field), do: size_field - 4

  # Behaviour definitions

  defmodule Readable do
    @moduledoc "Behaviour for packets that can be parsed from binary."

    @doc "Parse packet from a PacketReader."
    @callback read(reader :: term()) :: {:ok, struct(), term()} | {:error, term()}

    @doc "Return the opcode for this packet type."
    @callback opcode() :: atom()
  end

  defmodule Writable do
    @moduledoc "Behaviour for packets that can be serialized to binary."

    @doc "Serialize packet to a PacketWriter."
    @callback write(packet :: struct(), writer :: term()) :: {:ok, term()} | {:error, term()}

    @doc "Return the opcode for this packet type."
    @callback opcode() :: atom()
  end
end
