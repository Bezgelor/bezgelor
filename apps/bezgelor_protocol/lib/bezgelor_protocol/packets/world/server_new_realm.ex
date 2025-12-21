defmodule BezgelorProtocol.Packets.World.ServerNewRealm do
  @moduledoc """
  Packet sent when player selects a different realm from the realm list.

  ## Overview

  This packet instructs the client to disconnect and reconnect to a different
  realm server. Contains the new realm's connection info and a fresh session key.

  NOTE: Client only processes this message when on the RealmSelect screen.

  ## Packet Structure

  ```
  unused      : uint32           - Unused (0)
  session_key : 16 bytes         - New session key for target realm
  address     : uint32           - Target realm IP (network byte order)
  port        : uint16           - Target realm port
  unused2     : bool (1 bit)     - Unused
  realm_name  : wide_string      - Target realm display name
  flags       : 32 bits          - Realm flags
  type        : 2 bits           - 0=PVE, 1=PVP
  note_text_id: 21 bits          - String ID for realm note/MOTD
  ```
  """

  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  # Realm type constants
  @realm_type_pve 0
  @realm_type_pvp 1

  defstruct unused: 0,
            session_key: <<0::128>>,
            address: 0,
            port: 0,
            unused2: false,
            realm_name: "",
            flags: 0,
            type: 0,
            note_text_id: 0

  @type t :: %__MODULE__{
          unused: non_neg_integer(),
          session_key: binary(),
          address: non_neg_integer(),
          port: non_neg_integer(),
          unused2: boolean(),
          realm_name: String.t(),
          flags: non_neg_integer(),
          type: non_neg_integer(),
          note_text_id: non_neg_integer()
        }

  @impl true
  def opcode, do: :server_new_realm

  @impl true
  @spec write(t(), PacketWriter.t()) :: {:ok, PacketWriter.t()}
  def write(%__MODULE__{} = packet, writer) do
    # Unused (uint32)
    writer = PacketWriter.write_u32(writer, packet.unused)

    # Session key (16 bytes) - use write_bytes_bits to maintain bit stream
    session_key = ensure_16_bytes(packet.session_key)
    writer = PacketWriter.write_bytes_bits(writer, session_key)

    # Gateway: Address (uint32) + Port (uint16)
    writer = PacketWriter.write_u32(writer, packet.address)
    writer = PacketWriter.write_bits(writer, packet.port, 16)

    # Unused2 (bool = 1 bit)
    writer = PacketWriter.write_bits(writer, if(packet.unused2, do: 1, else: 0), 1)

    # RealmName (wide string)
    writer = PacketWriter.write_wide_string(writer, packet.realm_name || "")

    # Flags (32 bits)
    writer = PacketWriter.write_bits(writer, packet.flags, 32)

    # Type (2 bits)
    writer = PacketWriter.write_bits(writer, packet.type, 2)

    # NoteTextId (21 bits)
    writer = PacketWriter.write_bits(writer, packet.note_text_id, 21)

    # Flush remaining bits
    writer = PacketWriter.flush_bits(writer)

    {:ok, writer}
  end

  @doc """
  Build a ServerNewRealm packet from a realm database record.
  """
  @spec from_realm(map(), binary()) :: t()
  def from_realm(realm, session_key) do
    %__MODULE__{
      unused: 0,
      session_key: session_key,
      address: realm_address_to_uint32(realm.address),
      port: realm.port,
      unused2: false,
      realm_name: realm.name,
      flags: realm.flags || 0,
      type: realm_type_to_int(realm.type),
      note_text_id: realm.note_text_id || 0
    }
  end

  # Ensure session key is exactly 16 bytes
  defp ensure_16_bytes(key) when is_binary(key) and byte_size(key) == 16, do: key

  defp ensure_16_bytes(key) when is_binary(key) do
    # Pad or truncate to 16 bytes
    :binary.part(<<key::binary, 0::128>>, 0, 16)
  end

  defp ensure_16_bytes(_), do: <<0::128>>

  # Convert IP address string to uint32 in network byte order
  defp realm_address_to_uint32(address) when is_binary(address) do
    case :inet.parse_address(String.to_charlist(address)) do
      {:ok, {a, b, c, d}} ->
        # Network byte order (big endian)
        <<value::32>> = <<a, b, c, d>>
        value

      _ ->
        # Default to localhost
        <<value::32>> = <<127, 0, 0, 1>>
        value
    end
  end

  defp realm_address_to_uint32(address) when is_integer(address), do: address
  # 127.0.0.1
  defp realm_address_to_uint32(_), do: 0x7F000001

  # Convert realm type atom to integer
  defp realm_type_to_int(:pve), do: @realm_type_pve
  defp realm_type_to_int(:pvp), do: @realm_type_pvp
  defp realm_type_to_int(type) when is_integer(type), do: type
  defp realm_type_to_int(_), do: @realm_type_pve
end
