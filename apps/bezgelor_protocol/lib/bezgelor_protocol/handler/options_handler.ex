defmodule BezgelorProtocol.Handler.OptionsHandler do
  @moduledoc """
  Handles ClientOptions packets (opcode 0x012B).

  Sent by the client when game options/settings change.

  ## Packet Structure (from NexusForever)

  - Type: uint32 (OptionType enum)
  - NewValue: uint32

  ## OptionType Values

  - Casting: NewValue is a bitmask of CastingOptionFlags
  - SharedChallenge: NewValue indicates whether to allow shared challenges
  - Other types have their own interpretations
  """

  @behaviour BezgelorProtocol.Handler

  alias BezgelorProtocol.PacketReader

  require Logger

  @impl true
  def handle(payload, state) do
    reader = PacketReader.new(payload)

    with {:ok, option_type, reader} <- PacketReader.read_uint32(reader),
         {:ok, new_value, _reader} <- PacketReader.read_uint32(reader) do
      Logger.debug(
        "[Options] Type: #{option_type}, Value: #{new_value}"
      )

      # Store option in session for reference
      options = get_in(state.session_data, [:options]) || %{}
      options = Map.put(options, option_type, new_value)
      state = put_in(state.session_data[:options], options)

      # TODO: Persist options to database
      # TODO: Apply option effects (e.g., casting options)

      {:ok, state}
    else
      {:error, reason} ->
        Logger.warning("[Options] Failed to parse: #{inspect(reason)}")
        {:ok, state}
    end
  end
end
