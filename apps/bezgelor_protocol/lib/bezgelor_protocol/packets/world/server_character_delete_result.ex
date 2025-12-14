defmodule BezgelorProtocol.Packets.World.ServerCharacterDeleteResult do
  @moduledoc """
  Character deletion result.

  ## Overview

  Server response to ClientCharacterDelete indicating success or failure.

  ## Wire Format (from NexusForever)

  ```
  result : 6 bits - CharacterModifyResult code
  data   : uint32 - Additional data (guild count for DeleteFailed_GuildMaster)
  ```

  ## Result Codes (CharacterModifyResult)

  | Code | Name | Description |
  |------|------|-------------|
  | 0x00 | DeleteOk | Character deleted successfully |
  | 0x01 | DeleteFailed | General deletion failure |
  | 0x02 | DeleteFailed_GuildMaster | Cannot delete guild master |
  """

  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  # CharacterModifyResult codes for deletion
  @result_delete_ok 0x00
  @result_delete_failed 0x01
  @result_delete_failed_guild_master 0x02

  defstruct [
    :result,
    data: 0
  ]

  @type result :: :success | :failed | :guild_master

  @type t :: %__MODULE__{
          result: result(),
          data: non_neg_integer()
        }

  @impl true
  def opcode, do: :server_character_delete_result

  @impl true
  @spec write(t(), PacketWriter.t()) :: {:ok, PacketWriter.t()}
  def write(%__MODULE__{} = packet, writer) do
    result_code = result_to_code(packet.result)

    # Format: result (6 bits), data (uint32)
    writer =
      writer
      |> PacketWriter.write_bits(result_code, 6)
      |> PacketWriter.write_bits(packet.data, 32)
      |> PacketWriter.flush_bits()

    {:ok, writer}
  end

  @doc "Convert result atom to CharacterModifyResult code."
  @spec result_to_code(result()) :: non_neg_integer()
  def result_to_code(:success), do: @result_delete_ok
  def result_to_code(:failed), do: @result_delete_failed
  def result_to_code(:guild_master), do: @result_delete_failed_guild_master
  def result_to_code(_), do: @result_delete_failed

  @doc "Create a success response."
  @spec success() :: t()
  def success do
    %__MODULE__{result: :success, data: 0}
  end

  @doc "Create a failure response."
  @spec failure() :: t()
  def failure do
    %__MODULE__{result: :failed, data: 0}
  end

  @doc "Create a guild master failure response with count."
  @spec guild_master_failure(non_neg_integer()) :: t()
  def guild_master_failure(guild_count) do
    %__MODULE__{result: :guild_master, data: guild_count}
  end
end
