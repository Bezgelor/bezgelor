defmodule BezgelorProtocol.Packets.World.ServerPathInitialise do
  @moduledoc """
  Server packet to initialize the player's path data.

  Sent during character login to initialize the PathTracker UI.

  ## Wire Format (from NexusForever)

  ```
  active_path              : 3 bits - Current path (0=Soldier, 1=Settler, 2=Scientist, 3=Explorer)
  path_progress[4]         : 4x uint32 - XP for each path
  path_unlocked_mask       : 4 bits - Which paths are unlocked
  time_since_last_activate : float32 - Days since last path change (negative = cooldown active)
  ```
  """

  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct active_path: 0,
            path_progress: [0, 0, 0, 0],
            # All paths unlocked by default
            path_unlocked_mask: 0x0F,
            time_since_last_activate: 0.0

  @type t :: %__MODULE__{
          active_path: non_neg_integer(),
          path_progress: [non_neg_integer()],
          path_unlocked_mask: non_neg_integer(),
          time_since_last_activate: float()
        }

  @impl true
  def opcode, do: :server_path_initialise

  @impl true
  @spec write(t(), PacketWriter.t()) :: {:ok, PacketWriter.t()}
  def write(%__MODULE__{} = packet, writer) do
    # Active path (3 bits)
    writer = PacketWriter.write_bits(writer, packet.active_path, 3)

    # Path progress - 4 uint32 values (XP for each path)
    writer =
      Enum.reduce(packet.path_progress, writer, fn xp, w ->
        PacketWriter.write_bits(w, xp, 32)
      end)

    # Path unlocked mask (4 bits)
    writer = PacketWriter.write_bits(writer, packet.path_unlocked_mask, 4)

    # Flush bits before writing float
    writer = PacketWriter.flush_bits(writer)

    # Time since last activate (float32)
    writer = PacketWriter.write_f32(writer, packet.time_since_last_activate)

    {:ok, writer}
  end

  @doc "Create from character data"
  def from_character(character) do
    %__MODULE__{
      active_path: character.active_path || 0,
      # TODO: Load from character path progress
      path_progress: [0, 0, 0, 0],
      # All paths unlocked
      path_unlocked_mask: 0x0F,
      # No cooldown (30 days ago)
      time_since_last_activate: -30.0
    }
  end
end
