defmodule BezgelorProtocol.Packets.World.ServerCharacterCreate do
  @moduledoc """
  Character creation result.

  ## Overview

  Server response to ClientCharacterCreate indicating success or failure.

  ## Wire Format (from NexusForever)

  ```
  character_id : uint64 - New character ID (0 on failure)
  world_id     : uint32 - Starting world ID
  result       : 3 bits - Result code from CharacterModifyResult
  ```

  ## Result Codes (CharacterModifyResult)

  | Code | Name | Description |
  |------|------|-------------|
  | 0x03 | CreateOk | Character created successfully |
  | 0x04 | CreateFailed | General creation failure |
  | 0x06 | CreateFailed_UniqueName | Name already in use |
  | 0x09 | CreateFailed_AccountFull | Max characters reached |
  | 0x0A | CreateFailed_InvalidName | Name doesn't meet requirements |
  | 0x0B | CreateFailed_Faction | Race doesn't match faction |
  | 0x0C | CreateFailed_Internal | Internal server error |
  """

  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  # CharacterModifyResult codes (from NexusForever)
  @result_create_ok 0x03
  @result_create_failed 0x04
  # Suppress unused warning - keeping for documentation
  _ = @result_create_failed
  @result_unique_name 0x06
  @result_account_full 0x09
  @result_invalid_name 0x0A
  @result_faction 0x0B
  @result_internal 0x0C

  # Default world ID for new characters
  @default_world_id 870

  defstruct [
    :result,
    character_id: 0,
    world_id: @default_world_id
  ]

  @type result ::
          :success
          | :name_taken
          | :invalid_name
          | :max_characters
          | :invalid_faction
          | :server_error

  @type t :: %__MODULE__{
          result: result(),
          character_id: non_neg_integer(),
          world_id: non_neg_integer()
        }

  @impl true
  def opcode, do: :server_character_create

  @impl true
  @spec write(t(), PacketWriter.t()) :: {:ok, PacketWriter.t()}
  def write(%__MODULE__{} = packet, writer) do
    result_code = result_to_code(packet.result)

    # Format: character_id (uint64), world_id (uint32), result (3 bits)
    writer =
      writer
      |> PacketWriter.write_u64(packet.character_id)
      |> PacketWriter.write_u32(packet.world_id)
      |> PacketWriter.write_bits(result_code, 3)
      |> PacketWriter.flush_bits()

    {:ok, writer}
  end

  @doc "Convert result atom to CharacterModifyResult code."
  @spec result_to_code(result()) :: non_neg_integer()
  def result_to_code(:success), do: @result_create_ok
  def result_to_code(:name_taken), do: @result_unique_name
  def result_to_code(:invalid_name), do: @result_invalid_name
  def result_to_code(:max_characters), do: @result_account_full
  def result_to_code(:invalid_faction), do: @result_faction
  def result_to_code(:server_error), do: @result_internal
  def result_to_code(_), do: @result_internal

  @doc "Create a success response with character ID."
  @spec success(non_neg_integer()) :: t()
  def success(character_id) do
    %__MODULE__{result: :success, character_id: character_id, world_id: @default_world_id}
  end

  @doc "Create a success response with character ID and world ID."
  @spec success(non_neg_integer(), non_neg_integer()) :: t()
  def success(character_id, world_id) do
    %__MODULE__{result: :success, character_id: character_id, world_id: world_id}
  end

  @doc "Create a failure response."
  @spec failure(result()) :: t()
  def failure(reason) do
    %__MODULE__{result: reason, character_id: 0, world_id: 0}
  end
end
