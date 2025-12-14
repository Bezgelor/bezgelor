defmodule BezgelorProtocol.Packets.World.ServerInstanceSettings do
  @moduledoc """
  Server packet with instance settings.

  ## Packet Structure

  ```
  difficulty                     : 2 bits  - World difficulty
  prime_level                    : uint32  - Prime level
  flags                          : 8 bits  - World settings flags
  client_entity_send_update_interval : uint32 - Entity update interval (ms)
  ```
  """

  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct difficulty: 0,
            prime_level: 0,
            flags: 0,
            client_entity_send_update_interval: 125

  @type t :: %__MODULE__{
          difficulty: non_neg_integer(),
          prime_level: non_neg_integer(),
          flags: non_neg_integer(),
          client_entity_send_update_interval: non_neg_integer()
        }

  @impl true
  def opcode, do: :server_instance_settings

  @impl true
  @spec write(t(), PacketWriter.t()) :: {:ok, PacketWriter.t()}
  def write(%__MODULE__{} = packet, writer) do
    writer =
      writer
      |> PacketWriter.write_bits(packet.difficulty, 2)
      |> PacketWriter.write_bits(packet.prime_level, 32)
      |> PacketWriter.write_bits(packet.flags, 8)
      |> PacketWriter.write_bits(packet.client_entity_send_update_interval, 32)
      |> PacketWriter.flush_bits()

    {:ok, writer}
  end
end
