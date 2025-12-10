defmodule BezgelorProtocol.Packets.World.ServerCastResult do
  @moduledoc """
  Spell cast result notification.

  ## Overview

  Sent to inform the client about the result of a spell cast attempt.
  Used for both success and failure cases.

  ## Wire Format

  ```
  result       : uint8   - Result code (0=ok, 1=failed, 2=interrupted, etc.)
  reason       : uint8   - Failure reason code (if result != ok)
  spell_id     : uint32  - Spell that was attempted
  ```

  ## Result Codes

  | Code | Name | Description |
  |------|------|-------------|
  | 0 | ok | Cast succeeded |
  | 1 | failed | Generic failure |
  | 2 | interrupted | Cast was interrupted |

  ## Reason Codes (when result != ok)

  | Code | Name | Description |
  |------|------|-------------|
  | 0 | none | No specific reason |
  | 1 | not_known | Spell not learned |
  | 2 | cooldown | Spell on cooldown |
  | 3 | no_target | Target required |
  | 4 | invalid_target | Wrong target type |
  | 5 | out_of_range | Target too far |
  | 6 | no_resources | Not enough mana/energy |
  | 7 | silenced | Cannot cast spells |
  | 8 | moving | Cannot cast while moving |
  | 9 | already_casting | Already casting another spell |
  """

  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  # Result codes
  @result_ok 0
  @result_failed 1
  @result_interrupted 2

  # Reason codes
  @reason_none 0
  @reason_not_known 1
  @reason_cooldown 2
  @reason_no_target 3
  @reason_invalid_target 4
  @reason_out_of_range 5
  @reason_no_resources 6
  @reason_silenced 7
  @reason_moving 8
  @reason_already_casting 9

  defstruct [:result, :reason, :spell_id]

  @type result :: :ok | :failed | :interrupted
  @type reason ::
          :none
          | :not_known
          | :cooldown
          | :no_target
          | :invalid_target
          | :out_of_range
          | :no_resources
          | :silenced
          | :moving
          | :already_casting

  @type t :: %__MODULE__{
          result: result(),
          reason: reason(),
          spell_id: non_neg_integer()
        }

  @impl true
  def opcode, do: :server_cast_result

  @impl true
  @spec write(t(), PacketWriter.t()) :: {:ok, PacketWriter.t()}
  def write(%__MODULE__{} = packet, writer) do
    result_int = result_to_int(packet.result)
    reason_int = reason_to_int(packet.reason || :none)

    writer =
      writer
      |> PacketWriter.write_byte(result_int)
      |> PacketWriter.write_byte(reason_int)
      |> PacketWriter.write_uint32(packet.spell_id)

    {:ok, writer}
  end

  @doc """
  Create a success result.
  """
  @spec success(non_neg_integer()) :: t()
  def success(spell_id) do
    %__MODULE__{
      result: :ok,
      reason: :none,
      spell_id: spell_id
    }
  end

  @doc """
  Create a failure result.
  """
  @spec failure(non_neg_integer(), reason()) :: t()
  def failure(spell_id, reason) do
    %__MODULE__{
      result: :failed,
      reason: reason,
      spell_id: spell_id
    }
  end

  @doc """
  Create an interrupted result.
  """
  @spec interrupted(non_neg_integer()) :: t()
  def interrupted(spell_id) do
    %__MODULE__{
      result: :interrupted,
      reason: :none,
      spell_id: spell_id
    }
  end

  # Conversion functions

  @doc "Convert result atom to integer."
  @spec result_to_int(result()) :: non_neg_integer()
  def result_to_int(:ok), do: @result_ok
  def result_to_int(:failed), do: @result_failed
  def result_to_int(:interrupted), do: @result_interrupted
  def result_to_int(_), do: @result_failed

  @doc "Convert integer to result atom."
  @spec int_to_result(non_neg_integer()) :: result()
  def int_to_result(@result_ok), do: :ok
  def int_to_result(@result_failed), do: :failed
  def int_to_result(@result_interrupted), do: :interrupted
  def int_to_result(_), do: :failed

  @doc "Convert reason atom to integer."
  @spec reason_to_int(reason()) :: non_neg_integer()
  def reason_to_int(:none), do: @reason_none
  def reason_to_int(:not_known), do: @reason_not_known
  def reason_to_int(:cooldown), do: @reason_cooldown
  def reason_to_int(:no_target), do: @reason_no_target
  def reason_to_int(:invalid_target), do: @reason_invalid_target
  def reason_to_int(:out_of_range), do: @reason_out_of_range
  def reason_to_int(:no_resources), do: @reason_no_resources
  def reason_to_int(:silenced), do: @reason_silenced
  def reason_to_int(:moving), do: @reason_moving
  def reason_to_int(:already_casting), do: @reason_already_casting
  def reason_to_int(_), do: @reason_none

  @doc "Convert integer to reason atom."
  @spec int_to_reason(non_neg_integer()) :: reason()
  def int_to_reason(@reason_none), do: :none
  def int_to_reason(@reason_not_known), do: :not_known
  def int_to_reason(@reason_cooldown), do: :cooldown
  def int_to_reason(@reason_no_target), do: :no_target
  def int_to_reason(@reason_invalid_target), do: :invalid_target
  def int_to_reason(@reason_out_of_range), do: :out_of_range
  def int_to_reason(@reason_no_resources), do: :no_resources
  def int_to_reason(@reason_silenced), do: :silenced
  def int_to_reason(@reason_moving), do: :moving
  def int_to_reason(@reason_already_casting), do: :already_casting
  def int_to_reason(_), do: :none
end
