defmodule BezgelorProtocol.Packets.World.ServerSpellCancelCast do
  @moduledoc """
  Spell cast cancellation notification (Server07F9 in NexusForever).

  ## Overview

  Sent when an active spell cast is cancelled or interrupted. This is different
  from ServerCastResult which is sent for initial cast failures before casting
  actually starts.

  Use this packet to cancel an active cast (e.g., when the player releases the
  button for a charged spell before threshold, or when interrupted).

  ## Wire Format (per NexusForever Server07F9.cs)

  ```
  server_unique_id : uint32  - Casting ID from the corresponding ServerSpellStart
  cast_result      : 9 bits  - Result code from CastResult enum
  caster_id        : uint32  - Entity ID of the caster
  cancel_cast      : 1 bit   - True if this is cancelling the cast
  ```

  ## Common CastResult Values

  | Value | Name | Description |
  |-------|------|-------------|
  | 0 | Ok | Cast succeeded (not typically used with cancel) |
  | 6 | SpellCancelled | Player cancelled the spell |
  | 11 | SpellInterrupted | Spell was interrupted |
  | 97 | CasterMovement | Cancelled due to movement |
  """

  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct [:server_unique_id, :cast_result, :caster_id, :cancel_cast]

  # CastResult values (subset - see NexusForever CastResult.cs for full list)
  @cast_result_ok 0
  @cast_result_spell_cancelled 6
  @cast_result_spell_interrupted 11
  @cast_result_caster_movement 97

  @type cast_result ::
          :ok
          | :spell_cancelled
          | :spell_interrupted
          | :caster_movement
          | non_neg_integer()

  @type t :: %__MODULE__{
          server_unique_id: non_neg_integer(),
          cast_result: cast_result(),
          caster_id: non_neg_integer(),
          cancel_cast: boolean()
        }

  @impl true
  def opcode, do: :server_spell_cancel_cast

  @impl true
  @spec write(t(), PacketWriter.t()) :: {:ok, PacketWriter.t()}
  def write(%__MODULE__{} = packet, writer) do
    cast_result_int = cast_result_to_int(packet.cast_result)

    writer =
      writer
      |> PacketWriter.write_u32(packet.server_unique_id)
      |> PacketWriter.write_bits(cast_result_int, 9)
      |> PacketWriter.write_u32(packet.caster_id)
      |> PacketWriter.write_bits(if(packet.cancel_cast, do: 1, else: 0), 1)
      |> PacketWriter.flush_bits()

    {:ok, writer}
  end

  @doc """
  Create a spell cancellation packet.

  ## Parameters

  - `server_unique_id` - The casting_id from ServerSpellStart
  - `caster_id` - Entity ID of the caster
  - `cast_result` - Reason for cancellation (default: :spell_cancelled)
  """
  @spec new(non_neg_integer(), non_neg_integer(), cast_result()) :: t()
  def new(server_unique_id, caster_id, cast_result \\ :spell_cancelled) do
    %__MODULE__{
      server_unique_id: server_unique_id,
      cast_result: cast_result,
      caster_id: caster_id,
      cancel_cast: true
    }
  end

  @doc """
  Create a cancellation packet for player-initiated cancel.
  """
  @spec cancelled(non_neg_integer(), non_neg_integer()) :: t()
  def cancelled(server_unique_id, caster_id) do
    new(server_unique_id, caster_id, :spell_cancelled)
  end

  @doc """
  Create a cancellation packet for interrupt (e.g., stunned).
  """
  @spec interrupted(non_neg_integer(), non_neg_integer()) :: t()
  def interrupted(server_unique_id, caster_id) do
    new(server_unique_id, caster_id, :spell_interrupted)
  end

  @doc """
  Create a cancellation packet for movement interrupt.
  """
  @spec movement_cancelled(non_neg_integer(), non_neg_integer()) :: t()
  def movement_cancelled(server_unique_id, caster_id) do
    new(server_unique_id, caster_id, :caster_movement)
  end

  # Convert cast_result atom to integer
  defp cast_result_to_int(:ok), do: @cast_result_ok
  defp cast_result_to_int(:spell_cancelled), do: @cast_result_spell_cancelled
  defp cast_result_to_int(:spell_interrupted), do: @cast_result_spell_interrupted
  defp cast_result_to_int(:caster_movement), do: @cast_result_caster_movement
  defp cast_result_to_int(int) when is_integer(int), do: int
  defp cast_result_to_int(_), do: @cast_result_spell_cancelled
end
