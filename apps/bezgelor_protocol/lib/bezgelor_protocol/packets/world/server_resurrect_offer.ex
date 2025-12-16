defmodule BezgelorProtocol.Packets.World.ServerResurrectOffer do
  @moduledoc """
  Server notification of resurrection offer.

  ## Overview

  Sent to a dead player when another player casts a resurrection spell on them.
  The player can accept or decline the offer within the timeout period.

  ## Wire Format

  ```
  caster_guid    : uint64 - GUID of player offering resurrection
  caster_name    : string - Name of caster (for UI display)
  spell_id       : uint32 - Resurrection spell ID
  health_percent : float32 - Health % restored if accepted
  timeout_ms     : uint32 - Time to accept before offer expires
  ```
  """

  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct [:caster_guid, :caster_name, :spell_id, :health_percent, :timeout_ms]

  @type t :: %__MODULE__{
          caster_guid: non_neg_integer(),
          caster_name: String.t(),
          spell_id: non_neg_integer(),
          health_percent: float(),
          timeout_ms: non_neg_integer()
        }

  @doc """
  Create a new ServerResurrectOffer packet.

  ## Parameters

  - `caster_guid` - GUID of the player casting resurrection
  - `caster_name` - Display name of caster
  - `spell_id` - ID of the resurrection spell
  - `health_percent` - Percentage of health restored (e.g., 35.0 for 35%)
  - `timeout_ms` - Milliseconds before offer expires
  """
  @spec new(non_neg_integer(), String.t(), non_neg_integer(), float(), non_neg_integer()) :: t()
  def new(caster_guid, caster_name, spell_id, health_percent, timeout_ms) do
    %__MODULE__{
      caster_guid: caster_guid,
      caster_name: caster_name,
      spell_id: spell_id,
      health_percent: health_percent,
      timeout_ms: timeout_ms
    }
  end

  @impl true
  def opcode, do: :server_resurrect_offer

  @impl true
  @spec write(t(), PacketWriter.t()) :: {:ok, PacketWriter.t()}
  def write(%__MODULE__{} = packet, writer) do
    writer =
      writer
      |> PacketWriter.write_uint64(packet.caster_guid)
      |> PacketWriter.write_wide_string(packet.caster_name)
      |> PacketWriter.write_uint32(packet.spell_id)
      |> PacketWriter.write_float32(packet.health_percent)
      |> PacketWriter.write_uint32(packet.timeout_ms)

    {:ok, writer}
  end
end
