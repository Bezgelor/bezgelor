defmodule BezgelorProtocol.Packets.Realm.ClientHelloAuth do
  @moduledoc """
  Client authentication request for realm server (port 23115).

  Sent after receiving ServerHello on port 23115.
  Contains game token from STS server for validation.

  ## Packet Structure

  | Field | Type | Description |
  |-------|------|-------------|
  | build | uint32 | Client build version (must be 16042) |
  | crypt_key_integer | uint64 | Always 0x1588 |
  | email | wide_string | Account email address |
  | uuid_1 | 16 bytes | Client UUID |
  | game_token | 16 bytes | Token from STS server |
  | inet_address | uint32 | Client IP address |
  | language | uint32 | Language enum |
  | game_mode | uint32 | Game mode |
  | unused | uint32 | Unused field |
  | realm_datacenter_id | uint32 | Preferred datacenter |
  """

  @behaviour BezgelorProtocol.Packet.Readable

  alias BezgelorProtocol.PacketReader

  defstruct [
    :build,
    :crypt_key_integer,
    :email,
    :uuid_1,
    :game_token,
    :inet_address,
    :language,
    :game_mode,
    :unused,
    :realm_datacenter_id
  ]

  @type t :: %__MODULE__{
          build: non_neg_integer(),
          crypt_key_integer: non_neg_integer(),
          email: String.t(),
          uuid_1: binary(),
          game_token: binary(),
          inet_address: non_neg_integer(),
          language: non_neg_integer(),
          game_mode: non_neg_integer(),
          unused: non_neg_integer(),
          realm_datacenter_id: non_neg_integer()
        }

  @impl true
  def opcode, do: :client_hello_auth_realm

  @impl true
  def read(reader) do
    with {:ok, build, reader} <- PacketReader.read_uint32(reader),
         {:ok, crypt_key, reader} <- PacketReader.read_uint64(reader),
         {:ok, email, reader} <- PacketReader.read_wide_string(reader),
         {:ok, uuid_1, reader} <- PacketReader.read_bytes(reader, 16),
         {:ok, game_token, reader} <- PacketReader.read_bytes(reader, 16),
         {:ok, inet_address, reader} <- PacketReader.read_uint32(reader),
         {:ok, language, reader} <- PacketReader.read_uint32(reader),
         {:ok, game_mode, reader} <- PacketReader.read_uint32(reader),
         {:ok, unused, reader} <- PacketReader.read_uint32(reader),
         {:ok, datacenter_id, reader} <- read_datacenter_id(reader) do
      packet = %__MODULE__{
        build: build,
        crypt_key_integer: crypt_key,
        email: email,
        uuid_1: uuid_1,
        game_token: game_token,
        inet_address: inet_address,
        language: language,
        game_mode: game_mode,
        unused: unused,
        realm_datacenter_id: datacenter_id
      }

      {:ok, packet, reader}
    end
  end

  # Read datacenter ID, handling potential hardware info between
  # For now, skip any remaining bytes and read last uint32 as datacenter
  # Full hardware info parsing can be added later if needed
  defp read_datacenter_id(reader) do
    # Try to read datacenter_id directly
    # If there's more data (hardware info), we skip it for now
    case PacketReader.read_uint32(reader) do
      {:ok, value, reader} -> {:ok, value, reader}
      {:error, :eof} -> {:ok, 0, reader}
    end
  end
end
