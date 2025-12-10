defmodule BezgelorProtocol.Packets.World.ServerCharacterCreate do
  @moduledoc """
  Character creation result.

  ## Overview

  Server response to ClientCharacterCreate indicating success
  or failure with the new character ID.

  ## Wire Format

  ```
  result       : uint32 - Result code (0=success, other=error)
  character_id : uint64 - New character ID (0 on failure)
  ```

  ## Result Codes

  | Code | Name | Description |
  |------|------|-------------|
  | 0 | success | Character created successfully |
  | 1 | name_taken | Name already in use |
  | 2 | invalid_name | Name doesn't meet requirements |
  | 3 | max_characters | Account has maximum characters |
  | 4 | invalid_race | Invalid race selection |
  | 5 | invalid_class | Invalid class selection |
  | 6 | invalid_faction | Race doesn't match faction |
  | 7 | server_error | Internal server error |
  """

  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  # Result codes
  @result_success 0
  @result_name_taken 1
  @result_invalid_name 2
  @result_max_characters 3
  @result_invalid_race 4
  @result_invalid_class 5
  @result_invalid_faction 6
  @result_server_error 7

  defstruct [
    :result,
    character_id: 0
  ]

  @type result ::
          :success
          | :name_taken
          | :invalid_name
          | :max_characters
          | :invalid_race
          | :invalid_class
          | :invalid_faction
          | :server_error

  @type t :: %__MODULE__{
          result: result(),
          character_id: non_neg_integer()
        }

  @impl true
  def opcode, do: :server_character_create

  @impl true
  @spec write(t(), PacketWriter.t()) :: {:ok, PacketWriter.t()}
  def write(%__MODULE__{} = packet, writer) do
    result_code = result_to_code(packet.result)

    writer =
      writer
      |> PacketWriter.write_uint32(result_code)
      |> PacketWriter.write_uint64(packet.character_id)

    {:ok, writer}
  end

  @doc "Convert result atom to integer code."
  @spec result_to_code(result()) :: non_neg_integer()
  def result_to_code(:success), do: @result_success
  def result_to_code(:name_taken), do: @result_name_taken
  def result_to_code(:invalid_name), do: @result_invalid_name
  def result_to_code(:max_characters), do: @result_max_characters
  def result_to_code(:invalid_race), do: @result_invalid_race
  def result_to_code(:invalid_class), do: @result_invalid_class
  def result_to_code(:invalid_faction), do: @result_invalid_faction
  def result_to_code(:server_error), do: @result_server_error
  def result_to_code(_), do: @result_server_error

  @doc "Convert integer code to result atom."
  @spec code_to_result(non_neg_integer()) :: result()
  def code_to_result(@result_success), do: :success
  def code_to_result(@result_name_taken), do: :name_taken
  def code_to_result(@result_invalid_name), do: :invalid_name
  def code_to_result(@result_max_characters), do: :max_characters
  def code_to_result(@result_invalid_race), do: :invalid_race
  def code_to_result(@result_invalid_class), do: :invalid_class
  def code_to_result(@result_invalid_faction), do: :invalid_faction
  def code_to_result(_), do: :server_error

  @doc "Create a success response with character ID."
  @spec success(non_neg_integer()) :: t()
  def success(character_id) do
    %__MODULE__{result: :success, character_id: character_id}
  end

  @doc "Create a failure response."
  @spec failure(result()) :: t()
  def failure(reason) do
    %__MODULE__{result: reason, character_id: 0}
  end
end
