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
         {:ok, email, reader} <- PacketReader.read_wide_string_fixed(reader),
         {:ok, uuid_1, reader} <- PacketReader.read_bytes(reader, 16),
         {:ok, game_token, reader} <- PacketReader.read_bytes(reader, 16),
         {:ok, inet_address, reader} <- PacketReader.read_uint32(reader),
         {:ok, language, reader} <- PacketReader.read_uint32(reader),
         {:ok, game_mode, reader} <- PacketReader.read_uint32(reader),
         {:ok, unused, reader} <- PacketReader.read_uint32(reader),
         {:ok, reader} <- skip_hardware_info(reader),
         {:ok, datacenter_id, reader} <- PacketReader.read_uint32(reader) do
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

  # Skip hardware info (CPU, GPU, OS details)
  # Format: CpuInfo, uint32 MemoryPhysical, GpuInfo, 4x uint32 OS info
  defp skip_hardware_info(reader) do
    with {:ok, reader} <- skip_cpu_info(reader),
         {:ok, _memory, reader} <- PacketReader.read_uint32(reader),
         {:ok, reader} <- skip_gpu_info(reader),
         {:ok, _arch, reader} <- PacketReader.read_uint32(reader),
         {:ok, _os_ver, reader} <- PacketReader.read_uint32(reader),
         {:ok, _sp, reader} <- PacketReader.read_uint32(reader),
         {:ok, _prod_type, reader} <- PacketReader.read_uint32(reader) do
      {:ok, reader}
    end
  end

  # Skip CPU info: 3 wide strings + 5 uint32s
  defp skip_cpu_info(reader) do
    with {:ok, _manufacturer, reader} <- PacketReader.read_wide_string(reader),
         {:ok, _name, reader} <- PacketReader.read_wide_string(reader),
         {:ok, _desc, reader} <- PacketReader.read_wide_string(reader),
         {:ok, _family, reader} <- PacketReader.read_uint32(reader),
         {:ok, _level, reader} <- PacketReader.read_uint32(reader),
         {:ok, _revision, reader} <- PacketReader.read_uint32(reader),
         {:ok, _max_clock, reader} <- PacketReader.read_uint32(reader),
         {:ok, _num_cores, reader} <- PacketReader.read_uint32(reader) do
      {:ok, reader}
    end
  end

  # Skip GPU info: 1 wide string + 5 uint32s
  defp skip_gpu_info(reader) do
    with {:ok, _name, reader} <- PacketReader.read_wide_string(reader),
         {:ok, _vendor_id, reader} <- PacketReader.read_uint32(reader),
         {:ok, _device_id, reader} <- PacketReader.read_uint32(reader),
         {:ok, _subsys_id, reader} <- PacketReader.read_uint32(reader),
         {:ok, _revision, reader} <- PacketReader.read_uint32(reader),
         {:ok, _adapter_ram, reader} <- PacketReader.read_uint32(reader) do
      {:ok, reader}
    end
  end
end
