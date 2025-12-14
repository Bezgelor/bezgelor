defmodule BezgelorProtocol.Handler.LogoutHandler do
  @moduledoc """
  Handler for ClientLogoutRequest packets.

  Handles player logout/character switch requests. Currently performs
  instant logout without the 30-second countdown timer.

  ## Flow

  1. Client sends ClientLogoutRequest with Initiated=true to start logout
  2. Server sends ServerLogout with Requested=true to confirm
  3. Client returns to character select screen

  ## Future Enhancement

  Could implement the 30-second countdown timer like retail WildStar,
  allowing cancellation during the countdown period.
  """

  @behaviour BezgelorProtocol.Handler

  alias BezgelorProtocol.PacketReader
  alias BezgelorProtocol.PacketWriter

  require Logger

  # LogoutReason enum values (from NexusForever)
  @logout_reason_none 0

  @impl true
  def handle(payload, state) do
    reader = PacketReader.new(payload)

    # Read Initiated bit (1 bit)
    {:ok, initiated, _reader} = PacketReader.read_bits(reader, 1)
    initiated = initiated == 1

    if initiated do
      # Player wants to logout - perform instant logout
      Logger.info("Player logout requested (instant)")

      # Build ServerLogout response
      # Format: Requested (1 bit), Reason (5 bits)
      writer =
        PacketWriter.new()
        |> PacketWriter.write_bits(1, 1)  # Requested = true
        |> PacketWriter.write_bits(@logout_reason_none, 5)  # Reason = None
        |> PacketWriter.flush_bits()

      payload = PacketWriter.to_binary(writer)

      {:reply_world_encrypted, :server_logout, payload, state}
    else
      # Player cancelled logout - just acknowledge
      Logger.debug("Player logout cancelled")
      {:ok, state}
    end
  end
end
