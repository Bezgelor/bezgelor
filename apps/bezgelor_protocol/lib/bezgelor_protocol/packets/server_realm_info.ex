defmodule BezgelorProtocol.Packets.ServerRealmInfo do
  @moduledoc """
  Server realm information packet.

  Sent after successful authentication to provide realm server details.

  ## Fields

  - `account_id` - Account database ID
  - `realm_id` - Realm server ID
  - `realm_name` - Display name of the realm
  - `realm_address` - IP:port of realm server
  - `session_key` - 16-byte session key for realm auth

  ## Wire Format

  ```
  account_id:    uint32 (little-endian)
  realm_id:      uint32 (little-endian)
  realm_name:    wide_string (uint32 length + UTF-16LE)
  realm_address: string (null-terminated ASCII)
  session_key:   16 bytes
  ```
  """

  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct [
    :account_id,
    :realm_id,
    :realm_name,
    :realm_address,
    :session_key
  ]

  @type t :: %__MODULE__{
          account_id: non_neg_integer(),
          realm_id: non_neg_integer(),
          realm_name: String.t(),
          realm_address: String.t(),
          session_key: binary()
        }

  @impl true
  def opcode, do: :server_realm_info

  @impl true
  @spec write(t(), PacketWriter.t()) :: {:ok, PacketWriter.t()}
  def write(%__MODULE__{} = packet, writer) do
    writer =
      writer
      |> PacketWriter.write_u32(packet.account_id)
      |> PacketWriter.write_u32(packet.realm_id)
      |> PacketWriter.write_wide_string(packet.realm_name)
      |> PacketWriter.write_bytes_bits(packet.realm_address <> <<0>>)
      |> PacketWriter.write_bytes_bits(packet.session_key)

    {:ok, writer}
  end
end
