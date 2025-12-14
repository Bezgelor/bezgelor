defmodule BezgelorProtocol.Handler.ZoneChangeHandler do
  @moduledoc """
  Handles ClientZoneChange packets (opcode 0x063A).

  Sent by the client when crossing zone boundaries. Contains the previous
  and new zone IDs.

  ## Packet Structure (from NexusForever)

  - PreviousZoneId: 15 bits
  - NewZoneId: 15 bits
  """

  @behaviour BezgelorProtocol.Handler

  alias BezgelorProtocol.PacketReader

  require Logger

  @impl true
  def handle(payload, state) do
    reader = PacketReader.new(payload)

    with {:ok, previous_zone_id, reader} <- PacketReader.read_bits(reader, 15),
         {:ok, new_zone_id, _reader} <- PacketReader.read_bits(reader, 15) do
      Logger.info(
        "[ZoneChange] Player moved from zone #{previous_zone_id} to zone #{new_zone_id}"
      )

      # Update session data with current zone
      state = put_in(state.session_data[:zone_id], new_zone_id)
      state = put_in(state.session_data[:previous_zone_id], previous_zone_id)

      # TODO: Trigger zone-specific events (quests, achievements, etc.)
      # TODO: Update entity visibility based on new zone

      {:ok, state}
    else
      {:error, reason} ->
        Logger.warning("[ZoneChange] Failed to parse: #{inspect(reason)}")
        {:ok, state}
    end
  end
end
