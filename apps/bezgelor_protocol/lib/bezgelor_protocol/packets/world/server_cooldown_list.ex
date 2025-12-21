defmodule BezgelorProtocol.Packets.World.ServerCooldownList do
  @moduledoc """
  Full cooldown list sent to the client on login.

  ## Wire Format (from NexusForever)
    cooldown_count : uint32
    cooldowns      : [Cooldown] * count

  Cooldown:
    type           : 3 bits
    spell_id       : 18 bits
    type_id        : uint32
    time_remaining : uint32 (milliseconds)
  """

  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct cooldowns: []

  @type cooldown :: %{
          type: non_neg_integer(),
          spell_id: non_neg_integer(),
          type_id: non_neg_integer(),
          time_remaining: non_neg_integer()
        }

  @type t :: %__MODULE__{cooldowns: [cooldown()]}

  @impl true
  def opcode, do: :server_cooldown_list

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    writer = PacketWriter.write_u32(writer, length(packet.cooldowns))

    writer =
      Enum.reduce(packet.cooldowns, writer, fn cooldown, w ->
        w
        |> PacketWriter.write_bits(cooldown.type, 3)
        |> PacketWriter.write_bits(cooldown.spell_id, 18)
        |> PacketWriter.write_u32(cooldown.type_id)
        |> PacketWriter.write_u32(cooldown.time_remaining)
      end)

    {:ok, writer}
  end
end
