# Phase 2: Protocol Layer - Implementation Plan

**Status:** ✅ Complete

**Goal:** Implement WildStar network protocol parsing and TCP connection handling.

**Outcome:** Server accepts TCP connections, parses incoming packets into Elixir structs, can send packets back with proper framing and encryption.

---

## Overview

This phase creates the `bezgelor_protocol` app which handles:
1. Packet binary serialization/deserialization
2. TCP connection management with Ranch
3. Per-connection GenServer state machines
4. Packet encryption/decryption integration

### WildStar Packet Structure

```
┌──────────────┬──────────────┬─────────────────────┐
│ Size (4 bytes)│ Opcode (2 bytes)│ Payload (variable) │
└──────────────┴──────────────┴─────────────────────┘
```

- **Size**: Little-endian uint32, includes size field itself (so payload = size - 4)
- **Opcode**: Little-endian uint16, identifies message type
- **Payload**: Bit-packed data specific to each message

### Key Elixir Concepts Introduced

1. **Binary Pattern Matching**: `<<size::little-32, opcode::little-16, payload::binary>>`
2. **GenServer**: Stateful connection processes
3. **Ranch**: TCP acceptor pool
4. **Behaviours**: Define packet handler interface
5. **Protocols**: Alternative dispatch for packet serialization

---

## Tasks

### Batch 1: App Setup & Core Types (Tasks 1-3)

| Task | Description | Status |
|------|-------------|--------|
| 1 | Create bezgelor_protocol app with Ranch dependency | ✅ Done |
| 2 | Define GameMessageOpcode enum module | ✅ Done |
| 3 | Create Packet behaviour and base types | ✅ Done |

### Batch 2: Binary Parsing (Tasks 4-6)

| Task | Description | Status |
|------|-------------|--------|
| 4 | Implement PacketReader for bit-level parsing | ✅ Done |
| 5 | Implement PacketWriter for bit-level serialization | ✅ Done |
| 6 | Create packet framing module (header read/write) | ✅ Done |

### Batch 3: Connection Infrastructure (Tasks 7-9)

| Task | Description | Status |
|------|-------------|--------|
| 7 | Set up Ranch TCP acceptor | ✅ Done |
| 8 | Create Connection GenServer | ✅ Done |
| 9 | Implement packet send/receive pipeline | ✅ Done |

### Batch 4: Core Packets (Tasks 10-12)

| Task | Description | Status |
|------|-------------|--------|
| 10 | Implement ServerHello packet | ✅ Done |
| 11 | Implement ClientHelloAuth packet | ✅ Done |
| 12 | Implement encrypted packet wrappers | ✅ Done |

### Batch 5: Message Routing (Tasks 13-15)

| Task | Description | Status |
|------|-------------|--------|
| 13 | Create MessageRegistry for opcode → module mapping | ✅ Done |
| 14 | Define MessageHandler behaviour | ✅ Done |
| 15 | Integration test: echo server | ✅ Done |

---

## Task 1: Create bezgelor_protocol App

**Files:**
- Create: `apps/bezgelor_protocol/mix.exs`
- Create: `apps/bezgelor_protocol/lib/bezgelor_protocol.ex`
- Create: `apps/bezgelor_protocol/lib/bezgelor_protocol/application.ex`

**Step 1: Generate the app**

Run:
```bash
cd ./apps
mix new bezgelor_protocol --sup
```

**Step 2: Update mix.exs with dependencies**

Edit `apps/bezgelor_protocol/mix.exs`:

```elixir
defmodule BezgelorProtocol.MixProject do
  use Mix.Project

  def project do
    [
      app: :bezgelor_protocol,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {BezgelorProtocol.Application, []}
    ]
  end

  defp deps do
    [
      {:ranch, "~> 2.1"},
      {:bezgelor_crypto, in_umbrella: true}
    ]
  end
end
```

**Step 3: Install dependencies**

Run:
```bash
cd .
mix deps.get
```

**Step 4: Commit**

```bash
git add apps/bezgelor_protocol
git commit -m "chore: Add bezgelor_protocol app with Ranch dependency"
```

---

## Task 2: Define GameMessageOpcode Enum

**Files:**
- Create: `apps/bezgelor_protocol/lib/bezgelor_protocol/opcode.ex`
- Test: `apps/bezgelor_protocol/test/bezgelor_protocol/opcode_test.exs`

**Step 1: Write the test**

Create `apps/bezgelor_protocol/test/bezgelor_protocol/opcode_test.exs`:

```elixir
defmodule BezgelorProtocol.OpcodeTest do
  use ExUnit.Case, async: true

  alias BezgelorProtocol.Opcode

  describe "to_integer/1" do
    test "returns integer for known opcode" do
      assert Opcode.to_integer(:server_hello) == 0x0003
      assert Opcode.to_integer(:server_auth_encrypted) == 0x0076
      assert Opcode.to_integer(:client_hello_auth) == 0x0004
    end
  end

  describe "from_integer/1" do
    test "returns atom for known opcode" do
      assert Opcode.from_integer(0x0003) == {:ok, :server_hello}
      assert Opcode.from_integer(0x0076) == {:ok, :server_auth_encrypted}
    end

    test "returns error for unknown opcode" do
      assert Opcode.from_integer(0xFFFF) == {:error, :unknown_opcode}
    end
  end

  describe "name/1" do
    test "returns human-readable name" do
      assert Opcode.name(:server_hello) == "ServerHello"
      assert Opcode.name(:client_hello_auth) == "ClientHelloAuth"
    end
  end
end
```

**Step 2: Run test (expect failure)**

```bash
mix test apps/bezgelor_protocol/test/bezgelor_protocol/opcode_test.exs
```

**Step 3: Write the Opcode module**

Create `apps/bezgelor_protocol/lib/bezgelor_protocol/opcode.ex`:

```elixir
defmodule BezgelorProtocol.Opcode do
  @moduledoc """
  WildStar game message opcodes.

  ## Overview

  Opcodes are 16-bit identifiers for packet types. This module provides
  bidirectional mapping between atom names and integer values.

  The opcodes are derived from NexusForever's GameMessageOpcode enum.
  We define only the opcodes we need, adding more as we implement handlers.

  ## Usage

      iex> Opcode.to_integer(:server_hello)
      3

      iex> Opcode.from_integer(0x0003)
      {:ok, :server_hello}
  """

  # Auth Server Opcodes
  @server_hello 0x0003
  @client_hello_auth 0x0004
  @server_auth_accepted 0x0005
  @server_auth_denied 0x0006
  @server_auth_encrypted 0x0076
  @client_encrypted 0x0077

  # World Server Opcodes
  @client_hello_realm 0x0008
  @server_realm_encrypted 0x0079
  @server_character_list 0x0117
  @client_character_select 0x0118
  @client_entered_world 0x00F2

  # Mapping from atom to integer
  @opcode_map %{
    # Auth
    server_hello: @server_hello,
    client_hello_auth: @client_hello_auth,
    server_auth_accepted: @server_auth_accepted,
    server_auth_denied: @server_auth_denied,
    server_auth_encrypted: @server_auth_encrypted,
    client_encrypted: @client_encrypted,
    # World
    client_hello_realm: @client_hello_realm,
    server_realm_encrypted: @server_realm_encrypted,
    server_character_list: @server_character_list,
    client_character_select: @client_character_select,
    client_entered_world: @client_entered_world
  }

  # Reverse mapping from integer to atom
  @reverse_map Map.new(@opcode_map, fn {k, v} -> {v, k} end)

  # Human-readable names
  @names %{
    server_hello: "ServerHello",
    client_hello_auth: "ClientHelloAuth",
    server_auth_accepted: "ServerAuthAccepted",
    server_auth_denied: "ServerAuthDenied",
    server_auth_encrypted: "ServerAuthEncrypted",
    client_encrypted: "ClientEncrypted",
    client_hello_realm: "ClientHelloRealm",
    server_realm_encrypted: "ServerRealmEncrypted",
    server_character_list: "ServerCharacterList",
    client_character_select: "ClientCharacterSelect",
    client_entered_world: "ClientEnteredWorld"
  }

  @type t :: atom()

  @doc "Convert opcode atom to integer value."
  @spec to_integer(t()) :: non_neg_integer()
  def to_integer(opcode) when is_atom(opcode) do
    Map.fetch!(@opcode_map, opcode)
  end

  @doc "Convert integer to opcode atom."
  @spec from_integer(non_neg_integer()) :: {:ok, t()} | {:error, :unknown_opcode}
  def from_integer(value) when is_integer(value) do
    case Map.fetch(@reverse_map, value) do
      {:ok, opcode} -> {:ok, opcode}
      :error -> {:error, :unknown_opcode}
    end
  end

  @doc "Get human-readable name for opcode."
  @spec name(t()) :: String.t()
  def name(opcode) when is_atom(opcode) do
    Map.get(@names, opcode, Atom.to_string(opcode))
  end

  @doc "List all known opcodes."
  @spec all() :: [t()]
  def all, do: Map.keys(@opcode_map)
end
```

**Step 4: Run test (expect pass)**

```bash
mix test apps/bezgelor_protocol/test/bezgelor_protocol/opcode_test.exs
```

**Step 5: Commit**

```bash
git add apps/bezgelor_protocol/lib/bezgelor_protocol/opcode.ex
git add apps/bezgelor_protocol/test/bezgelor_protocol/opcode_test.exs
git commit -m "feat(protocol): Add GameMessageOpcode enum module"
```

---

## Task 3: Create Packet Behaviour and Base Types

**Files:**
- Create: `apps/bezgelor_protocol/lib/bezgelor_protocol/packet.ex`
- Test: `apps/bezgelor_protocol/test/bezgelor_protocol/packet_test.exs`

**Step 1: Write the test**

Create `apps/bezgelor_protocol/test/bezgelor_protocol/packet_test.exs`:

```elixir
defmodule BezgelorProtocol.PacketTest do
  use ExUnit.Case, async: true

  alias BezgelorProtocol.Packet

  describe "header constants" do
    test "header size is 6 bytes" do
      assert Packet.header_size() == 6
    end
  end

  describe "parse_header/1" do
    test "parses valid header" do
      # Size = 10, Opcode = 3 (ServerHello)
      header = <<10, 0, 0, 0, 3, 0>>
      assert {:ok, 10, 0x0003} = Packet.parse_header(header)
    end

    test "returns error for incomplete header" do
      assert {:error, :incomplete} = Packet.parse_header(<<1, 2, 3>>)
    end
  end

  describe "build_header/2" do
    test "builds header from size and opcode" do
      header = Packet.build_header(10, 0x0003)
      assert header == <<10, 0, 0, 0, 3, 0>>
    end
  end
end
```

**Step 2: Run test (expect failure)**

```bash
mix test apps/bezgelor_protocol/test/bezgelor_protocol/packet_test.exs
```

**Step 3: Write the Packet module**

Create `apps/bezgelor_protocol/lib/bezgelor_protocol/packet.ex`:

```elixir
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
  Calculate total packet size from payload size.

  The size field includes itself (4 bytes) but not the opcode (2 bytes).
  Total packet = 4 (size) + 2 (opcode) + payload
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
    @callback read(reader :: term()) :: {:ok, struct()} | {:error, term()}

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
```

**Step 4: Run test (expect pass)**

```bash
mix test apps/bezgelor_protocol/test/bezgelor_protocol/packet_test.exs
```

**Step 5: Commit**

```bash
git add apps/bezgelor_protocol/lib/bezgelor_protocol/packet.ex
git add apps/bezgelor_protocol/test/bezgelor_protocol/packet_test.exs
git commit -m "feat(protocol): Add Packet behaviour and header parsing"
```

---

## Task 4: Implement PacketReader

**Files:**
- Create: `apps/bezgelor_protocol/lib/bezgelor_protocol/packet_reader.ex`
- Test: `apps/bezgelor_protocol/test/bezgelor_protocol/packet_reader_test.exs`

**Step 1: Write the test**

Create `apps/bezgelor_protocol/test/bezgelor_protocol/packet_reader_test.exs`:

```elixir
defmodule BezgelorProtocol.PacketReaderTest do
  use ExUnit.Case, async: true

  alias BezgelorProtocol.PacketReader

  describe "new/1" do
    test "creates reader from binary" do
      reader = PacketReader.new(<<1, 2, 3, 4>>)
      assert is_struct(reader, PacketReader)
    end
  end

  describe "read_byte/1" do
    test "reads single byte" do
      reader = PacketReader.new(<<0xAB, 0xCD>>)
      assert {:ok, 0xAB, reader} = PacketReader.read_byte(reader)
      assert {:ok, 0xCD, _reader} = PacketReader.read_byte(reader)
    end
  end

  describe "read_uint16/1" do
    test "reads little-endian uint16" do
      reader = PacketReader.new(<<0x34, 0x12>>)
      assert {:ok, 0x1234, _reader} = PacketReader.read_uint16(reader)
    end
  end

  describe "read_uint32/1" do
    test "reads little-endian uint32" do
      reader = PacketReader.new(<<0x78, 0x56, 0x34, 0x12>>)
      assert {:ok, 0x12345678, _reader} = PacketReader.read_uint32(reader)
    end
  end

  describe "read_uint64/1" do
    test "reads little-endian uint64" do
      reader = PacketReader.new(<<0xEF, 0xCD, 0xAB, 0x89, 0x67, 0x45, 0x23, 0x01>>)
      assert {:ok, 0x0123456789ABCDEF, _reader} = PacketReader.read_uint64(reader)
    end
  end

  describe "read_bytes/2" do
    test "reads specified number of bytes" do
      reader = PacketReader.new(<<1, 2, 3, 4, 5>>)
      assert {:ok, <<1, 2, 3>>, reader} = PacketReader.read_bytes(reader, 3)
      assert {:ok, <<4, 5>>, _reader} = PacketReader.read_bytes(reader, 2)
    end
  end

  describe "read_string/1" do
    test "reads null-terminated string" do
      reader = PacketReader.new(<<"hello", 0, "world">>)
      assert {:ok, "hello", _reader} = PacketReader.read_string(reader)
    end
  end

  describe "read_wide_string/1" do
    test "reads UTF-16LE string with length prefix" do
      # Length = 5, then "hello" in UTF-16LE
      data = <<5, 0, 0, 0>> <> :unicode.characters_to_binary("hello", :utf8, {:utf16, :little})
      reader = PacketReader.new(data)
      assert {:ok, "hello", _reader} = PacketReader.read_wide_string(reader)
    end
  end

  describe "read_bits/2" do
    test "reads specified number of bits" do
      # Binary: 0b11010110 = 0xD6
      reader = PacketReader.new(<<0xD6>>)
      # Read 5 bits: should get 0b10110 = 22
      assert {:ok, 22, reader} = PacketReader.read_bits(reader, 5)
      # Read 3 bits: should get 0b110 = 6
      assert {:ok, 6, _reader} = PacketReader.read_bits(reader, 3)
    end
  end
end
```

**Step 2: Run test (expect failure)**

```bash
mix test apps/bezgelor_protocol/test/bezgelor_protocol/packet_reader_test.exs
```

**Step 3: Write the PacketReader module**

Create `apps/bezgelor_protocol/lib/bezgelor_protocol/packet_reader.ex`:

```elixir
defmodule BezgelorProtocol.PacketReader do
  @moduledoc """
  Bit-level packet reader for WildStar protocol.

  ## Overview

  WildStar packets use bit-packed serialization. This reader supports both
  byte-aligned and bit-level reads, maintaining position state.

  ## Example

      reader = PacketReader.new(binary_data)
      {:ok, value, reader} = PacketReader.read_uint32(reader)
      {:ok, bits, reader} = PacketReader.read_bits(reader, 5)
  """

  defstruct [:data, :byte_pos, :bit_pos, :bit_value]

  @type t :: %__MODULE__{
          data: binary(),
          byte_pos: non_neg_integer(),
          bit_pos: non_neg_integer(),
          bit_value: non_neg_integer()
        }

  @doc "Create a new reader from binary data."
  @spec new(binary()) :: t()
  def new(data) when is_binary(data) do
    %__MODULE__{
      data: data,
      byte_pos: 0,
      bit_pos: 0,
      bit_value: 0
    }
  end

  @doc "Read a single byte."
  @spec read_byte(t()) :: {:ok, non_neg_integer(), t()} | {:error, :eof}
  def read_byte(%__MODULE__{} = reader) do
    reader = flush_bits(reader)

    case read_raw_bytes(reader, 1) do
      {:ok, <<byte>>, reader} -> {:ok, byte, reader}
      error -> error
    end
  end

  @doc "Read a little-endian uint16."
  @spec read_uint16(t()) :: {:ok, non_neg_integer(), t()} | {:error, :eof}
  def read_uint16(%__MODULE__{} = reader) do
    reader = flush_bits(reader)

    case read_raw_bytes(reader, 2) do
      {:ok, <<value::little-16>>, reader} -> {:ok, value, reader}
      error -> error
    end
  end

  @doc "Read a little-endian uint32."
  @spec read_uint32(t()) :: {:ok, non_neg_integer(), t()} | {:error, :eof}
  def read_uint32(%__MODULE__{} = reader) do
    reader = flush_bits(reader)

    case read_raw_bytes(reader, 4) do
      {:ok, <<value::little-32>>, reader} -> {:ok, value, reader}
      error -> error
    end
  end

  @doc "Read a little-endian uint64."
  @spec read_uint64(t()) :: {:ok, non_neg_integer(), t()} | {:error, :eof}
  def read_uint64(%__MODULE__{} = reader) do
    reader = flush_bits(reader)

    case read_raw_bytes(reader, 8) do
      {:ok, <<value::little-64>>, reader} -> {:ok, value, reader}
      error -> error
    end
  end

  @doc "Read specified number of bytes."
  @spec read_bytes(t(), non_neg_integer()) :: {:ok, binary(), t()} | {:error, :eof}
  def read_bytes(%__MODULE__{} = reader, count) when count >= 0 do
    reader = flush_bits(reader)
    read_raw_bytes(reader, count)
  end

  @doc "Read a null-terminated ASCII string."
  @spec read_string(t()) :: {:ok, String.t(), t()} | {:error, :eof}
  def read_string(%__MODULE__{data: data, byte_pos: pos} = reader) do
    reader = flush_bits(reader)

    case find_null(data, pos) do
      {:ok, null_pos} ->
        length = null_pos - pos
        <<_::binary-size(pos), string::binary-size(length), 0, _::binary>> = data
        {:ok, string, %{reader | byte_pos: null_pos + 1}}

      :error ->
        {:error, :eof}
    end
  end

  @doc "Read a UTF-16LE string with uint32 length prefix."
  @spec read_wide_string(t()) :: {:ok, String.t(), t()} | {:error, term()}
  def read_wide_string(%__MODULE__{} = reader) do
    with {:ok, length, reader} <- read_uint32(reader),
         {:ok, utf16_data, reader} <- read_bytes(reader, length * 2) do
      case :unicode.characters_to_binary(utf16_data, {:utf16, :little}, :utf8) do
        string when is_binary(string) -> {:ok, string, reader}
        _ -> {:error, :invalid_utf16}
      end
    end
  end

  @doc "Read specified number of bits."
  @spec read_bits(t(), pos_integer()) :: {:ok, non_neg_integer(), t()} | {:error, :eof}
  def read_bits(%__MODULE__{} = reader, count) when count > 0 do
    read_bits_acc(reader, count, 0, 0)
  end

  # Private functions

  defp read_raw_bytes(%__MODULE__{data: data, byte_pos: pos} = reader, count) do
    if byte_size(data) >= pos + count do
      <<_::binary-size(pos), bytes::binary-size(count), _::binary>> = data
      {:ok, bytes, %{reader | byte_pos: pos + count}}
    else
      {:error, :eof}
    end
  end

  defp flush_bits(%__MODULE__{bit_pos: 0} = reader), do: reader

  defp flush_bits(%__MODULE__{bit_pos: bit_pos, byte_pos: byte_pos} = reader) when bit_pos > 0 do
    %{reader | bit_pos: 0, bit_value: 0, byte_pos: byte_pos + 1}
  end

  defp read_bits_acc(reader, 0, value, _shift), do: {:ok, value, reader}

  defp read_bits_acc(%__MODULE__{bit_pos: 0} = reader, remaining, value, shift) do
    case read_raw_bytes(reader, 1) do
      {:ok, <<byte>>, new_reader} ->
        reader = %{new_reader | bit_pos: 0, bit_value: byte, byte_pos: new_reader.byte_pos - 1}
        read_bits_acc(reader, remaining, value, shift)

      error ->
        error
    end
  end

  defp read_bits_acc(%__MODULE__{bit_pos: bit_pos, bit_value: bit_value} = reader, remaining, value, shift)
       when bit_pos == 0 do
    # Need to read a new byte
    case read_raw_bytes(%{reader | byte_pos: reader.byte_pos}, 1) do
      {:ok, <<byte>>, new_reader} ->
        bits_available = 8
        bits_to_read = min(remaining, bits_available)
        mask = (1 <<< bits_to_read) - 1
        bits = Bitwise.band(byte, mask)
        new_value = Bitwise.bor(value, Bitwise.bsl(bits, shift))
        new_bit_pos = bits_to_read
        new_bit_value = Bitwise.bsr(byte, bits_to_read)

        new_reader =
          if new_bit_pos == 8 do
            %{new_reader | bit_pos: 0, bit_value: 0}
          else
            %{new_reader | bit_pos: new_bit_pos, bit_value: new_bit_value, byte_pos: new_reader.byte_pos - 1}
          end

        read_bits_acc(new_reader, remaining - bits_to_read, new_value, shift + bits_to_read)

      error ->
        error
    end
  end

  defp read_bits_acc(%__MODULE__{bit_pos: bit_pos, bit_value: bit_value, byte_pos: byte_pos} = reader, remaining, value, shift) do
    bits_available = 8 - bit_pos
    bits_to_read = min(remaining, bits_available)
    mask = (1 <<< bits_to_read) - 1
    bits = Bitwise.band(bit_value, mask)
    new_value = Bitwise.bor(value, Bitwise.bsl(bits, shift))
    new_bit_pos = bit_pos + bits_to_read
    new_bit_value = Bitwise.bsr(bit_value, bits_to_read)

    new_reader =
      if new_bit_pos == 8 do
        %{reader | bit_pos: 0, bit_value: 0, byte_pos: byte_pos + 1}
      else
        %{reader | bit_pos: new_bit_pos, bit_value: new_bit_value}
      end

    read_bits_acc(new_reader, remaining - bits_to_read, new_value, shift + bits_to_read)
  end

  defp find_null(data, pos) do
    case :binary.match(data, <<0>>, scope: {pos, byte_size(data) - pos}) do
      {null_pos, 1} -> {:ok, null_pos}
      :nomatch -> :error
    end
  end
end
```

**Step 4: Run test (expect pass)**

```bash
mix test apps/bezgelor_protocol/test/bezgelor_protocol/packet_reader_test.exs
```

**Step 5: Commit**

```bash
git add apps/bezgelor_protocol/lib/bezgelor_protocol/packet_reader.ex
git add apps/bezgelor_protocol/test/bezgelor_protocol/packet_reader_test.exs
git commit -m "feat(protocol): Add PacketReader for bit-level parsing"
```

---

## Task 5: Implement PacketWriter

**Files:**
- Create: `apps/bezgelor_protocol/lib/bezgelor_protocol/packet_writer.ex`
- Test: `apps/bezgelor_protocol/test/bezgelor_protocol/packet_writer_test.exs`

**Step 1: Write the test**

Create `apps/bezgelor_protocol/test/bezgelor_protocol/packet_writer_test.exs`:

```elixir
defmodule BezgelorProtocol.PacketWriterTest do
  use ExUnit.Case, async: true

  alias BezgelorProtocol.PacketWriter

  describe "new/0" do
    test "creates empty writer" do
      writer = PacketWriter.new()
      assert is_struct(writer, PacketWriter)
    end
  end

  describe "write_byte/2" do
    test "writes single byte" do
      writer = PacketWriter.new()
      writer = PacketWriter.write_byte(writer, 0xAB)
      assert PacketWriter.to_binary(writer) == <<0xAB>>
    end
  end

  describe "write_uint16/2" do
    test "writes little-endian uint16" do
      writer = PacketWriter.new()
      writer = PacketWriter.write_uint16(writer, 0x1234)
      assert PacketWriter.to_binary(writer) == <<0x34, 0x12>>
    end
  end

  describe "write_uint32/2" do
    test "writes little-endian uint32" do
      writer = PacketWriter.new()
      writer = PacketWriter.write_uint32(writer, 0x12345678)
      assert PacketWriter.to_binary(writer) == <<0x78, 0x56, 0x34, 0x12>>
    end
  end

  describe "write_uint64/2" do
    test "writes little-endian uint64" do
      writer = PacketWriter.new()
      writer = PacketWriter.write_uint64(writer, 0x0123456789ABCDEF)
      assert PacketWriter.to_binary(writer) == <<0xEF, 0xCD, 0xAB, 0x89, 0x67, 0x45, 0x23, 0x01>>
    end
  end

  describe "write_bytes/2" do
    test "writes raw bytes" do
      writer = PacketWriter.new()
      writer = PacketWriter.write_bytes(writer, <<1, 2, 3>>)
      assert PacketWriter.to_binary(writer) == <<1, 2, 3>>
    end
  end

  describe "write_wide_string/2" do
    test "writes UTF-16LE string with length prefix" do
      writer = PacketWriter.new()
      writer = PacketWriter.write_wide_string(writer, "hello")
      binary = PacketWriter.to_binary(writer)

      # Should have 4-byte length prefix (5) + 10 bytes of UTF-16LE
      assert byte_size(binary) == 14
      <<length::little-32, utf16::binary>> = binary
      assert length == 5
      assert :unicode.characters_to_binary(utf16, {:utf16, :little}, :utf8) == "hello"
    end
  end

  describe "write_bits/3" do
    test "writes specified number of bits" do
      writer = PacketWriter.new()
      writer = PacketWriter.write_bits(writer, 22, 5)  # 0b10110
      writer = PacketWriter.write_bits(writer, 6, 3)   # 0b110
      writer = PacketWriter.flush_bits(writer)
      # Combined: 0b110_10110 = 0xD6
      assert PacketWriter.to_binary(writer) == <<0xD6>>
    end
  end
end
```

**Step 2: Run test (expect failure)**

```bash
mix test apps/bezgelor_protocol/test/bezgelor_protocol/packet_writer_test.exs
```

**Step 3: Write the PacketWriter module**

Create `apps/bezgelor_protocol/lib/bezgelor_protocol/packet_writer.ex`:

```elixir
defmodule BezgelorProtocol.PacketWriter do
  @moduledoc """
  Bit-level packet writer for WildStar protocol.

  ## Overview

  WildStar packets use bit-packed serialization. This writer supports both
  byte-aligned and bit-level writes, building up binary data.

  ## Example

      writer = PacketWriter.new()
      |> PacketWriter.write_uint32(12345)
      |> PacketWriter.write_bits(3, 5)  # 3 in 5 bits
      |> PacketWriter.flush_bits()

      binary = PacketWriter.to_binary(writer)
  """

  defstruct [:buffer, :bit_pos, :bit_value]

  @type t :: %__MODULE__{
          buffer: iodata(),
          bit_pos: non_neg_integer(),
          bit_value: non_neg_integer()
        }

  @doc "Create a new empty writer."
  @spec new() :: t()
  def new do
    %__MODULE__{
      buffer: [],
      bit_pos: 0,
      bit_value: 0
    }
  end

  @doc "Convert writer contents to binary."
  @spec to_binary(t()) :: binary()
  def to_binary(%__MODULE__{buffer: buffer}) do
    IO.iodata_to_binary(buffer)
  end

  @doc "Write a single byte."
  @spec write_byte(t(), non_neg_integer()) :: t()
  def write_byte(%__MODULE__{} = writer, byte) when byte >= 0 and byte <= 255 do
    writer
    |> flush_bits()
    |> append_bytes(<<byte>>)
  end

  @doc "Write a little-endian uint16."
  @spec write_uint16(t(), non_neg_integer()) :: t()
  def write_uint16(%__MODULE__{} = writer, value) do
    writer
    |> flush_bits()
    |> append_bytes(<<value::little-16>>)
  end

  @doc "Write a little-endian uint32."
  @spec write_uint32(t(), non_neg_integer()) :: t()
  def write_uint32(%__MODULE__{} = writer, value) do
    writer
    |> flush_bits()
    |> append_bytes(<<value::little-32>>)
  end

  @doc "Write a little-endian uint64."
  @spec write_uint64(t(), non_neg_integer()) :: t()
  def write_uint64(%__MODULE__{} = writer, value) do
    writer
    |> flush_bits()
    |> append_bytes(<<value::little-64>>)
  end

  @doc "Write raw bytes."
  @spec write_bytes(t(), binary()) :: t()
  def write_bytes(%__MODULE__{} = writer, bytes) when is_binary(bytes) do
    writer
    |> flush_bits()
    |> append_bytes(bytes)
  end

  @doc "Write a UTF-16LE string with uint32 length prefix."
  @spec write_wide_string(t(), String.t()) :: t()
  def write_wide_string(%__MODULE__{} = writer, string) when is_binary(string) do
    utf16 = :unicode.characters_to_binary(string, :utf8, {:utf16, :little})
    length = String.length(string)

    writer
    |> write_uint32(length)
    |> write_bytes(utf16)
  end

  @doc "Write specified number of bits."
  @spec write_bits(t(), non_neg_integer(), pos_integer()) :: t()
  def write_bits(%__MODULE__{} = writer, value, count) when count > 0 do
    write_bits_acc(writer, value, count)
  end

  @doc "Flush any remaining bits to the buffer."
  @spec flush_bits(t()) :: t()
  def flush_bits(%__MODULE__{bit_pos: 0} = writer), do: writer

  def flush_bits(%__MODULE__{bit_pos: bit_pos, bit_value: bit_value} = writer) when bit_pos > 0 do
    writer
    |> append_bytes(<<bit_value>>)
    |> Map.put(:bit_pos, 0)
    |> Map.put(:bit_value, 0)
  end

  # Private functions

  defp append_bytes(%__MODULE__{buffer: buffer} = writer, bytes) do
    %{writer | buffer: [buffer, bytes]}
  end

  defp write_bits_acc(writer, _value, 0), do: writer

  defp write_bits_acc(%__MODULE__{bit_pos: bit_pos, bit_value: bit_value} = writer, value, remaining) do
    bits_available = 8 - bit_pos
    bits_to_write = min(remaining, bits_available)
    mask = (1 <<< bits_to_write) - 1
    bits = Bitwise.band(value, mask)

    new_bit_value = Bitwise.bor(bit_value, Bitwise.bsl(bits, bit_pos))
    new_bit_pos = bit_pos + bits_to_write

    writer =
      if new_bit_pos == 8 do
        writer
        |> append_bytes(<<new_bit_value>>)
        |> Map.put(:bit_pos, 0)
        |> Map.put(:bit_value, 0)
      else
        %{writer | bit_pos: new_bit_pos, bit_value: new_bit_value}
      end

    write_bits_acc(writer, Bitwise.bsr(value, bits_to_write), remaining - bits_to_write)
  end
end
```

**Step 4: Run test (expect pass)**

```bash
mix test apps/bezgelor_protocol/test/bezgelor_protocol/packet_writer_test.exs
```

**Step 5: Commit**

```bash
git add apps/bezgelor_protocol/lib/bezgelor_protocol/packet_writer.ex
git add apps/bezgelor_protocol/test/bezgelor_protocol/packet_writer_test.exs
git commit -m "feat(protocol): Add PacketWriter for bit-level serialization"
```

---

## Task 6: Create Packet Framing Module

**Files:**
- Create: `apps/bezgelor_protocol/lib/bezgelor_protocol/framing.ex`
- Test: `apps/bezgelor_protocol/test/bezgelor_protocol/framing_test.exs`

**Step 1: Write the test**

Create `apps/bezgelor_protocol/test/bezgelor_protocol/framing_test.exs`:

```elixir
defmodule BezgelorProtocol.FramingTest do
  use ExUnit.Case, async: true

  alias BezgelorProtocol.Framing

  describe "frame_packet/2" do
    test "frames payload with header" do
      payload = <<1, 2, 3, 4>>
      opcode = 0x0003

      framed = Framing.frame_packet(opcode, payload)

      # Size = 4 (size field) + 4 (payload) = 8
      # Header = 8 (size) + 3 (opcode) = 6 bytes
      assert framed == <<8, 0, 0, 0, 3, 0, 1, 2, 3, 4>>
    end
  end

  describe "parse_packets/1" do
    test "parses single complete packet" do
      data = <<8, 0, 0, 0, 3, 0, 1, 2, 3, 4>>

      assert {:ok, [{0x0003, <<1, 2, 3, 4>>}], <<>>} = Framing.parse_packets(data)
    end

    test "parses multiple packets" do
      packet1 = <<6, 0, 0, 0, 3, 0, 1, 2>>
      packet2 = <<5, 0, 0, 0, 4, 0, 0xFF>>
      data = packet1 <> packet2

      assert {:ok, packets, <<>>} = Framing.parse_packets(data)
      assert length(packets) == 2
      assert {0x0003, <<1, 2>>} in packets
      assert {0x0004, <<0xFF>>} in packets
    end

    test "returns remaining data for incomplete packet" do
      # Complete packet + incomplete
      complete = <<6, 0, 0, 0, 3, 0, 1, 2>>
      incomplete = <<10, 0, 0, 0, 4, 0>>  # Says 10 bytes but only 6 present

      data = complete <> incomplete

      assert {:ok, [{0x0003, <<1, 2>>}], ^incomplete} = Framing.parse_packets(data)
    end

    test "returns all data when header incomplete" do
      data = <<6, 0, 0>>  # Only 3 bytes, need 6 for header

      assert {:ok, [], ^data} = Framing.parse_packets(data)
    end
  end
end
```

**Step 2: Run test (expect failure)**

```bash
mix test apps/bezgelor_protocol/test/bezgelor_protocol/framing_test.exs
```

**Step 3: Write the Framing module**

Create `apps/bezgelor_protocol/lib/bezgelor_protocol/framing.ex`:

```elixir
defmodule BezgelorProtocol.Framing do
  @moduledoc """
  Packet framing for WildStar protocol.

  ## Overview

  Handles assembling and disassembling packets from/to the wire format.
  Packets are length-prefixed with a 6-byte header.

  ## Wire Format

      ┌──────────────┬──────────────┬─────────────────────┐
      │ Size (4 bytes)│ Opcode (2 bytes)│ Payload (variable) │
      └──────────────┴──────────────┴─────────────────────┘

  Size includes itself (4 bytes), so payload_length = size - 4.
  """

  alias BezgelorProtocol.Packet

  @header_size Packet.header_size()

  @doc """
  Frame a packet payload with header for transmission.

  Returns the complete packet binary ready to send.
  """
  @spec frame_packet(non_neg_integer(), binary()) :: binary()
  def frame_packet(opcode, payload) when is_binary(payload) do
    size = Packet.packet_size(byte_size(payload))
    header = Packet.build_header(size, opcode)
    header <> payload
  end

  @doc """
  Parse packets from a binary buffer.

  Returns `{:ok, packets, remaining}` where:
  - `packets` is a list of `{opcode, payload}` tuples
  - `remaining` is any leftover data (incomplete packet)

  This function extracts as many complete packets as possible.
  """
  @spec parse_packets(binary()) :: {:ok, [{non_neg_integer(), binary()}], binary()}
  def parse_packets(data) when is_binary(data) do
    parse_packets_acc(data, [])
  end

  defp parse_packets_acc(data, acc) when byte_size(data) < @header_size do
    {:ok, Enum.reverse(acc), data}
  end

  defp parse_packets_acc(data, acc) do
    case Packet.parse_header(binary_part(data, 0, @header_size)) do
      {:ok, size, opcode} ->
        payload_size = Packet.payload_size(size)
        total_size = @header_size + payload_size

        if byte_size(data) >= total_size do
          payload = binary_part(data, @header_size, payload_size)
          remaining = binary_part(data, total_size, byte_size(data) - total_size)
          parse_packets_acc(remaining, [{opcode, payload} | acc])
        else
          {:ok, Enum.reverse(acc), data}
        end

      {:error, _} ->
        {:ok, Enum.reverse(acc), data}
    end
  end
end
```

**Step 4: Run test (expect pass)**

```bash
mix test apps/bezgelor_protocol/test/bezgelor_protocol/framing_test.exs
```

**Step 5: Commit**

```bash
git add apps/bezgelor_protocol/lib/bezgelor_protocol/framing.ex
git add apps/bezgelor_protocol/test/bezgelor_protocol/framing_test.exs
git commit -m "feat(protocol): Add packet framing for wire format"
```

---

## Task 7: Set Up Ranch TCP Acceptor

**Files:**
- Modify: `apps/bezgelor_protocol/lib/bezgelor_protocol/application.ex`
- Create: `apps/bezgelor_protocol/lib/bezgelor_protocol/tcp_listener.ex`
- Test: `apps/bezgelor_protocol/test/bezgelor_protocol/tcp_listener_test.exs`

**Step 1: Write the test**

Create `apps/bezgelor_protocol/test/bezgelor_protocol/tcp_listener_test.exs`:

```elixir
defmodule BezgelorProtocol.TcpListenerTest do
  use ExUnit.Case

  alias BezgelorProtocol.TcpListener

  describe "start_link/1" do
    test "starts TCP listener on specified port" do
      opts = [
        port: 0,  # Random available port
        handler: BezgelorProtocol.Connection,
        name: :test_listener
      ]

      {:ok, _pid} = TcpListener.start_link(opts)

      # Verify we can get the port
      port = TcpListener.get_port(:test_listener)
      assert is_integer(port)
      assert port > 0

      # Clean up
      TcpListener.stop(:test_listener)
    end
  end
end
```

**Step 2: Run test (expect failure)**

```bash
mix test apps/bezgelor_protocol/test/bezgelor_protocol/tcp_listener_test.exs
```

**Step 3: Write the TcpListener module**

Create `apps/bezgelor_protocol/lib/bezgelor_protocol/tcp_listener.ex`:

```elixir
defmodule BezgelorProtocol.TcpListener do
  @moduledoc """
  TCP listener wrapper around Ranch.

  ## Overview

  Manages a Ranch listener that accepts TCP connections and spawns
  connection handler processes.

  ## Example

      # Start a listener
      {:ok, _} = TcpListener.start_link(
        port: 6600,
        handler: MyConnectionHandler,
        name: :auth_listener
      )

      # Get the actual port (useful when port: 0)
      port = TcpListener.get_port(:auth_listener)
  """

  require Logger

  @doc """
  Start a TCP listener.

  ## Options

  - `:port` - Port to listen on (required, use 0 for random)
  - `:handler` - Connection handler module (required)
  - `:name` - Listener name atom (required)
  - `:num_acceptors` - Number of acceptor processes (default: 10)
  - `:handler_opts` - Options passed to handler (default: [])
  """
  @spec start_link(keyword()) :: {:ok, pid()} | {:error, term()}
  def start_link(opts) do
    port = Keyword.fetch!(opts, :port)
    handler = Keyword.fetch!(opts, :handler)
    name = Keyword.fetch!(opts, :name)
    num_acceptors = Keyword.get(opts, :num_acceptors, 10)
    handler_opts = Keyword.get(opts, :handler_opts, [])

    transport_opts = %{
      socket_opts: [port: port],
      num_acceptors: num_acceptors
    }

    Logger.info("Starting TCP listener #{name} on port #{port}")

    :ranch.start_listener(
      name,
      :ranch_tcp,
      transport_opts,
      handler,
      handler_opts
    )
  end

  @doc "Get the port a listener is bound to."
  @spec get_port(atom()) :: non_neg_integer()
  def get_port(name) do
    :ranch.get_port(name)
  end

  @doc "Stop a listener."
  @spec stop(atom()) :: :ok
  def stop(name) do
    :ranch.stop_listener(name)
  end

  @doc "Get connection count for a listener."
  @spec connection_count(atom()) :: non_neg_integer()
  def connection_count(name) do
    :ranch.procs(name, :connections) |> length()
  end
end
```

**Step 4: Run test (expect failure - handler doesn't exist yet)**

We need to create a basic Connection module first. Let's do that in the next task.

**Step 5: Commit (partial)**

```bash
git add apps/bezgelor_protocol/lib/bezgelor_protocol/tcp_listener.ex
git commit -m "feat(protocol): Add TcpListener wrapper for Ranch"
```

---

## Task 8: Create Connection GenServer

**Files:**
- Create: `apps/bezgelor_protocol/lib/bezgelor_protocol/connection.ex`
- Test: `apps/bezgelor_protocol/test/bezgelor_protocol/connection_test.exs`

**Step 1: Write the test**

Create `apps/bezgelor_protocol/test/bezgelor_protocol/connection_test.exs`:

```elixir
defmodule BezgelorProtocol.ConnectionTest do
  use ExUnit.Case

  alias BezgelorProtocol.{Connection, TcpListener, Framing, Opcode}

  @moduletag :capture_log

  describe "connection lifecycle" do
    setup do
      # Start a test listener
      opts = [
        port: 0,
        handler: Connection,
        name: :test_conn_listener,
        handler_opts: [connection_type: :auth]
      ]

      {:ok, _} = TcpListener.start_link(opts)
      port = TcpListener.get_port(:test_conn_listener)

      on_exit(fn ->
        TcpListener.stop(:test_conn_listener)
      end)

      %{port: port}
    end

    test "accepts connection and sends ServerHello", %{port: port} do
      # Connect to the server
      {:ok, socket} = :gen_tcp.connect(~c"localhost", port, [:binary, active: false])

      # Should receive ServerHello packet
      {:ok, data} = :gen_tcp.recv(socket, 0, 5000)

      # Parse the packet
      {:ok, [{opcode, _payload}], _} = Framing.parse_packets(data)

      assert opcode == Opcode.to_integer(:server_hello)

      :gen_tcp.close(socket)
    end
  end
end
```

**Step 2: Run test (expect failure)**

```bash
mix test apps/bezgelor_protocol/test/bezgelor_protocol/connection_test.exs
```

**Step 3: Write the Connection module**

Create `apps/bezgelor_protocol/lib/bezgelor_protocol/connection.ex`:

```elixir
defmodule BezgelorProtocol.Connection do
  @moduledoc """
  GenServer handling a single client TCP connection.

  ## Overview

  Each connected client gets a dedicated Connection process that:
  - Receives data from the socket
  - Assembles packets from the data stream
  - Decrypts packets when encryption is enabled
  - Dispatches packets to handlers
  - Encrypts and sends outgoing packets

  ## Connection Types

  - `:auth` - Auth server connection (sends ConnectionType=3)
  - `:world` - World server connection (sends ConnectionType=11)

  ## State Machine

  1. `connected` - Initial state, sends ServerHello
  2. `authenticating` - Awaiting client authentication
  3. `authenticated` - Client is authenticated
  4. `disconnected` - Connection closed

  ## Ranch Protocol

  This module implements the Ranch protocol behaviour for TCP connections.
  """

  use GenServer
  require Logger

  alias BezgelorProtocol.{Framing, Opcode, PacketWriter}
  alias BezgelorCrypto.PacketCrypt

  @behaviour :ranch_protocol

  defstruct [
    :socket,
    :transport,
    :connection_type,
    :buffer,
    :encryption,
    :state,
    :session_data
  ]

  @type connection_type :: :auth | :world
  @type connection_state :: :connected | :authenticating | :authenticated | :disconnected

  @type t :: %__MODULE__{
          socket: :inet.socket(),
          transport: module(),
          connection_type: connection_type(),
          buffer: binary(),
          encryption: PacketCrypt.t() | nil,
          state: connection_state(),
          session_data: map()
        }

  # Ranch protocol callback
  @impl :ranch_protocol
  def start_link(ref, transport, opts) do
    pid = :proc_lib.spawn_link(__MODULE__, :init, [{ref, transport, opts}])
    {:ok, pid}
  end

  @doc false
  def init({ref, transport, opts}) do
    {:ok, socket} = :ranch.handshake(ref)
    :ok = transport.setopts(socket, active: :once, packet: :raw, binary: true)

    connection_type = Keyword.get(opts, :connection_type, :auth)

    state = %__MODULE__{
      socket: socket,
      transport: transport,
      connection_type: connection_type,
      buffer: <<>>,
      encryption: nil,
      state: :connected,
      session_data: %{}
    }

    # Initialize encryption with auth build key
    auth_key = PacketCrypt.key_from_auth_build()
    encryption = PacketCrypt.new(auth_key)
    state = %{state | encryption: encryption}

    # Send ServerHello
    state = send_server_hello(state)

    :gen_server.enter_loop(__MODULE__, [], state)
  end

  @impl GenServer
  def handle_info({:tcp, socket, data}, %{socket: socket, buffer: buffer} = state) do
    # Re-enable active mode
    state.transport.setopts(socket, active: :once)

    # Append to buffer and parse packets
    new_buffer = buffer <> data
    state = %{state | buffer: new_buffer}

    case process_buffer(state) do
      {:ok, state} ->
        {:noreply, state}

      {:error, reason} ->
        Logger.warning("Packet processing error: #{inspect(reason)}")
        {:stop, :normal, state}
    end
  end

  def handle_info({:tcp_closed, socket}, %{socket: socket} = state) do
    Logger.debug("Connection closed by client")
    {:stop, :normal, %{state | state: :disconnected}}
  end

  def handle_info({:tcp_error, socket, reason}, %{socket: socket} = state) do
    Logger.warning("TCP error: #{inspect(reason)}")
    {:stop, :normal, %{state | state: :disconnected}}
  end

  # Public API

  @doc "Send a packet to the client."
  @spec send_packet(pid(), atom(), binary()) :: :ok
  def send_packet(pid, opcode, payload) do
    GenServer.cast(pid, {:send_packet, opcode, payload})
  end

  @impl GenServer
  def handle_cast({:send_packet, opcode, payload}, state) do
    state = do_send_packet(state, opcode, payload)
    {:noreply, state}
  end

  # Private functions

  defp send_server_hello(state) do
    # Build ServerHello packet
    # AuthVersion = 16042, RealmId = 1, etc.
    connection_type_value = if state.connection_type == :auth, do: 3, else: 11

    writer = PacketWriter.new()
    |> PacketWriter.write_uint32(16042)  # AuthVersion
    |> PacketWriter.write_uint32(1)      # RealmId
    |> PacketWriter.write_uint32(1)      # RealmGroupId
    |> PacketWriter.write_uint32(0x97998A0)  # AuthMessage
    |> PacketWriter.write_bits(connection_type_value, 5)  # ConnectionType
    |> PacketWriter.write_bits(0, 11)    # Unused bits to align
    |> PacketWriter.flush_bits()

    payload = PacketWriter.to_binary(writer)
    do_send_packet(state, :server_hello, payload)
  end

  defp do_send_packet(%{socket: socket, transport: transport} = state, opcode, payload) do
    opcode_int = if is_atom(opcode), do: Opcode.to_integer(opcode), else: opcode
    packet = Framing.frame_packet(opcode_int, payload)

    case transport.send(socket, packet) do
      :ok ->
        Logger.debug("Sent packet: #{Opcode.name(opcode)} (#{byte_size(payload)} bytes)")
        state

      {:error, reason} ->
        Logger.warning("Failed to send packet: #{inspect(reason)}")
        state
    end
  end

  defp process_buffer(%{buffer: buffer} = state) do
    case Framing.parse_packets(buffer) do
      {:ok, packets, remaining} ->
        state = %{state | buffer: remaining}
        process_packets(packets, state)
    end
  end

  defp process_packets([], state), do: {:ok, state}

  defp process_packets([{opcode, payload} | rest], state) do
    case handle_packet(opcode, payload, state) do
      {:ok, state} ->
        process_packets(rest, state)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp handle_packet(opcode, payload, state) do
    case Opcode.from_integer(opcode) do
      {:ok, opcode_atom} ->
        Logger.debug("Received packet: #{Opcode.name(opcode_atom)} (#{byte_size(payload)} bytes)")
        # TODO: Dispatch to packet handlers
        {:ok, state}

      {:error, :unknown_opcode} ->
        Logger.warning("Unknown opcode: 0x#{Integer.to_string(opcode, 16)}")
        {:ok, state}
    end
  end
end
```

**Step 4: Run tests**

```bash
mix test apps/bezgelor_protocol/test/bezgelor_protocol/connection_test.exs
mix test apps/bezgelor_protocol/test/bezgelor_protocol/tcp_listener_test.exs
```

**Step 5: Commit**

```bash
git add apps/bezgelor_protocol/lib/bezgelor_protocol/connection.ex
git add apps/bezgelor_protocol/test/bezgelor_protocol/connection_test.exs
git add apps/bezgelor_protocol/test/bezgelor_protocol/tcp_listener_test.exs
git commit -m "feat(protocol): Add Connection GenServer with Ranch integration"
```

---

## Remaining Tasks (9-15) - Summary

The plan continues with:

**Task 9: Implement packet send/receive pipeline** - Add encryption to send/receive flow

**Task 10: Implement ServerHello packet struct** - Proper packet definition with Readable/Writable

**Task 11: Implement ClientHelloAuth packet struct** - Parse client auth request

**Task 12: Implement encrypted packet wrappers** - ServerAuthEncrypted, ClientEncrypted

**Task 13: Create MessageRegistry** - Maps opcodes to handler modules

**Task 14: Define MessageHandler behaviour** - Interface for packet handlers

**Task 15: Integration test** - End-to-end test with echo server

---

## Success Criteria

| # | Criterion | Status |
|---|-----------|--------|
| 1 | `bezgelor_protocol` app exists with Ranch dependency | ✅ Done |
| 2 | Can parse WildStar packet headers (6-byte format) | ✅ Done |
| 3 | PacketReader/Writer support bit-level operations | ✅ Done |
| 4 | TCP listener accepts connections on configured port | ✅ Done |
| 5 | Connection GenServer manages per-client state | ✅ Done |
| 6 | ServerHello packet sent on connection | ✅ Done |
| 7 | Packet encryption/decryption integrated | ✅ Done |
| 8 | Message routing dispatches to handlers | ✅ Done |
| 9 | All tests pass | ✅ Done |

---

## Dependencies

**From Phase 1:**
- `bezgelor_crypto.PacketCrypt` - Packet encryption/decryption

**New Dependencies:**
- `ranch ~> 2.1` - TCP acceptor pool

---

## Next Phase Preview

**Phase 3: Authentication** will:
- Implement auth server on port 6600
- Handle SRP6 authentication handshake
- Create/verify accounts via `bezgelor_db`
- Generate session tickets for world server

---

## Implementation Notes

**Files Implemented:**

*Core Modules:*
- `apps/bezgelor_protocol/lib/bezgelor_protocol/opcode.ex` - GameMessageOpcode enum
- `apps/bezgelor_protocol/lib/bezgelor_protocol/packet.ex` - Packet behaviour and header parsing
- `apps/bezgelor_protocol/lib/bezgelor_protocol/packet_reader.ex` - Bit-level packet parsing
- `apps/bezgelor_protocol/lib/bezgelor_protocol/packet_writer.ex` - Bit-level packet serialization
- `apps/bezgelor_protocol/lib/bezgelor_protocol/framing.ex` - Packet framing for wire format

*Connection Infrastructure:*
- `apps/bezgelor_protocol/lib/bezgelor_protocol/tcp_listener.ex` - Ranch TCP acceptor wrapper
- `apps/bezgelor_protocol/lib/bezgelor_protocol/connection.ex` - Connection GenServer

*Message Routing:*
- `apps/bezgelor_protocol/lib/bezgelor_protocol/packet_registry.ex` - Opcode to module mapping
- `apps/bezgelor_protocol/lib/bezgelor_protocol/handler.ex` - MessageHandler behaviour

*Packets:*
- `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/client_hello_auth.ex` - Client auth request

*Tests:*
- `apps/bezgelor_protocol/test/bezgelor_protocol/opcode_test.exs`
- `apps/bezgelor_protocol/test/bezgelor_protocol/packet_test.exs`
- `apps/bezgelor_protocol/test/bezgelor_protocol/packet_reader_test.exs`
- `apps/bezgelor_protocol/test/bezgelor_protocol/packet_writer_test.exs`
- `apps/bezgelor_protocol/test/bezgelor_protocol/framing_test.exs`
- `apps/bezgelor_protocol/test/bezgelor_protocol/tcp_listener_test.exs`
- `apps/bezgelor_protocol/test/bezgelor_protocol/connection_test.exs`
- `apps/bezgelor_protocol/test/bezgelor_protocol/packet_registry_test.exs`

**Design Notes:**
- MessageRegistry was implemented as `PacketRegistry` for clearer naming
- ServerHello packet built inline in `connection.ex` rather than as separate packet module
- Handler behaviour defined in `handler.ex` module
