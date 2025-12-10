defmodule BezgelorProtocol.Packets.Realm.ServerRealmInfo do
  @moduledoc """
  Realm server details for client connection.

  Contains World Server address and session credentials.

  ## Packet Structure

  | Field | Type | Description |
  |-------|------|-------------|
  | address | uint32 | World server IP (network byte order) |
  | port | uint16 | World server port |
  | session_key | 16 bytes | Session key for world auth |
  | account_id | uint32 | Account ID |
  | realm_name | wide_string | Realm display name |
  | flags | uint32 | RealmFlag bitfield |
  | type_and_note | uint32 | Type (2 bits) + NoteTextId (21 bits) |

  ## Realm Types

  - `:pve` (0) - Player vs Environment
  - `:pvp` (1) - Player vs Player

  ## Realm Flags

  - `0x10` - FactionRestricted
  """

  @behaviour BezgelorProtocol.Packet.Writable

  import Bitwise
  alias BezgelorProtocol.PacketWriter

  @realm_type_pve 0
  @realm_type_pvp 1

  defstruct [
    :address,
    :port,
    :session_key,
    :account_id,
    :realm_name,
    flags: 0,
    type: @realm_type_pve,
    note_text_id: 0
  ]

  @type realm_type :: :pve | :pvp | 0 | 1

  @type t :: %__MODULE__{
          address: non_neg_integer(),
          port: non_neg_integer(),
          session_key: binary(),
          account_id: non_neg_integer(),
          realm_name: String.t(),
          flags: non_neg_integer(),
          type: realm_type(),
          note_text_id: non_neg_integer()
        }

  @impl true
  def opcode, do: :server_realm_info

  @impl true
  @spec write(t(), PacketWriter.t()) :: {:ok, PacketWriter.t()}
  def write(%__MODULE__{} = packet, writer) do
    type_int = realm_type_to_int(packet.type)
    # Pack type (2 bits) and note_text_id (21 bits) into a uint32
    type_and_note = (type_int &&& 0x3) ||| ((packet.note_text_id &&& 0x1FFFFF) <<< 2)

    # Address is written as raw bytes in network order (big-endian)
    address_bytes = <<packet.address::big-unsigned-32>>

    writer =
      writer
      |> PacketWriter.write_bytes(address_bytes)
      |> PacketWriter.write_uint16(packet.port)
      |> PacketWriter.write_bytes(packet.session_key)
      |> PacketWriter.write_uint32(packet.account_id)
      |> PacketWriter.write_wide_string(packet.realm_name)
      |> PacketWriter.write_uint32(packet.flags)
      |> PacketWriter.write_uint32(type_and_note)

    {:ok, writer}
  end

  @doc "Convert realm type atom to integer."
  @spec realm_type_to_int(realm_type()) :: 0 | 1
  def realm_type_to_int(:pve), do: @realm_type_pve
  def realm_type_to_int(:pvp), do: @realm_type_pvp
  def realm_type_to_int(n) when n in [0, 1], do: n

  @doc "Convert IP string to network byte order uint32."
  @spec ip_to_uint32(String.t()) :: non_neg_integer()
  def ip_to_uint32(ip_string) when is_binary(ip_string) do
    [a, b, c, d] =
      ip_string
      |> String.split(".")
      |> Enum.map(&String.to_integer/1)

    <<n::big-unsigned-32>> = <<a, b, c, d>>
    n
  end
end
