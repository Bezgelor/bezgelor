defmodule BezgelorWorld.Handler.DuelHandler do
  @moduledoc """
  Handler for duel-related packets.

  ## Overview

  Processes player duel requests:
  - Initiating duel challenges
  - Responding to duel requests (accept/decline)
  - Canceling pending requests
  - Forfeiting active duels

  ## Packets Handled

  - ClientDuelRequest
  - ClientDuelResponse
  - ClientDuelCancel
  """

  @behaviour BezgelorProtocol.Handler

  alias BezgelorProtocol.Packets.World.{
    ClientDuelRequest,
    ClientDuelResponse,
    ClientDuelCancel,
    ServerDuelRequest,
    ServerDuelCountdown,
    ServerDuelResult
  }

  alias BezgelorProtocol.{PacketReader, PacketWriter}
  alias BezgelorWorld.PvP.DuelManager

  require Logger

  @countdown_seconds 5
  @request_timeout_seconds 30

  @impl true
  def handle(payload, state) do
    reader = PacketReader.new(payload)

    with {:error, _} <- handle_duel_request(reader, state),
         {:error, _} <- handle_duel_response(reader, state),
         {:error, _} <- handle_duel_cancel(reader, state) do
      Logger.warning("DuelHandler: Unknown packet format")
      {:error, :unknown_packet}
    end
  end

  # Handle duel request packet
  defp handle_duel_request(reader, state) do
    case ClientDuelRequest.read(reader) do
      {:ok, packet, _reader} ->
        process_duel_request(packet, state)

      {:error, _reason} ->
        {:error, :not_duel_request}
    end
  end

  # Handle duel response packet
  defp handle_duel_response(reader, state) do
    case ClientDuelResponse.read(reader) do
      {:ok, packet, _reader} ->
        process_duel_response(packet, state)

      {:error, _reason} ->
        {:error, :not_duel_response}
    end
  end

  # Handle duel cancel packet
  defp handle_duel_cancel(reader, state) do
    case ClientDuelCancel.read(reader) do
      {:ok, packet, _reader} ->
        process_duel_cancel(packet, state)

      {:error, _reason} ->
        {:error, :not_duel_cancel}
    end
  end

  defp process_duel_request(packet, state) do
    unless state.session_data[:in_world] do
      Logger.warning("DuelRequest received before player entered world")
      {:error, :not_in_world}
    else
      entity_guid = state.session_data[:entity_guid]
      character_name = state.session_data[:character_name] || "Unknown"
      position = state.session_data[:position] || {0.0, 0.0, 0.0}

      # Get target info - in a real implementation we'd look this up
      target_guid = packet.target_guid
      target_name = packet.target_name || "Target"

      case DuelManager.request_duel(entity_guid, character_name, target_guid, target_name, position) do
        {:ok, _duel_id} ->
          Logger.info("Duel request sent: #{character_name} -> #{target_name}")

          # Send duel request to target (would need to route to their session)
          # For now, send notification that request was sent
          send_duel_request_to_target(entity_guid, character_name, target_guid, state)

        {:error, :already_in_duel} ->
          Logger.debug("Player already in duel")
          {:error, :already_in_duel}

        {:error, :target_in_duel} ->
          Logger.debug("Target already in duel")
          {:error, :target_in_duel}

        {:error, :target_has_pending_request} ->
          Logger.debug("Target has pending duel request")
          {:error, :target_has_pending_request}

        {:error, reason} ->
          Logger.warning("Duel request failed: #{reason}")
          {:error, reason}
      end
    end
  end

  defp process_duel_response(packet, state) do
    unless state.session_data[:in_world] do
      Logger.warning("DuelResponse received before player entered world")
      {:error, :not_in_world}
    else
      entity_guid = state.session_data[:entity_guid]
      challenger_guid = packet.challenger_guid
      accepted = packet.accepted

      case DuelManager.respond_to_duel(entity_guid, challenger_guid, accepted) do
        {:ok, duel} when is_map(duel) ->
          # Duel accepted - send countdown to both players
          Logger.info("Duel accepted, starting countdown")
          send_duel_countdown(duel, state)

        {:ok, :declined} ->
          Logger.info("Duel declined")
          {:ok, state}

        {:error, :no_pending_request} ->
          Logger.debug("No pending duel request")
          {:error, :no_pending_request}

        {:error, :wrong_challenger} ->
          Logger.debug("Wrong challenger for duel response")
          {:error, :wrong_challenger}

        {:error, reason} ->
          Logger.warning("Duel response failed: #{reason}")
          {:error, reason}
      end
    end
  end

  defp process_duel_cancel(packet, state) do
    unless state.session_data[:in_world] do
      Logger.warning("DuelCancel received before player entered world")
      {:error, :not_in_world}
    else
      entity_guid = state.session_data[:entity_guid]
      target_guid = packet.target_guid

      case DuelManager.cancel_request(entity_guid, target_guid) do
        :ok ->
          Logger.info("Duel request cancelled")
          {:ok, state}

        {:error, :no_pending_request} ->
          Logger.debug("No pending duel request to cancel")
          {:error, :no_pending_request}

        {:error, reason} ->
          Logger.warning("Duel cancel failed: #{reason}")
          {:error, reason}
      end
    end
  end

  @doc """
  Handle duel forfeit from a player.
  Called when a player wants to give up during an active duel.
  """
  @spec forfeit_duel(non_neg_integer()) :: {:ok, map()} | {:error, atom()}
  def forfeit_duel(player_guid) do
    case DuelManager.forfeit_duel(player_guid) do
      {:ok, duel} ->
        Logger.info("Player #{player_guid} forfeited duel")
        {:ok, duel}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Report damage dealt during a duel.
  Called by combat system when damage is dealt between duelists.
  """
  @spec report_duel_damage(non_neg_integer(), non_neg_integer(), non_neg_integer()) ::
          {:ok, :continue} | {:ok, :ended, map()} | {:error, atom()}
  def report_duel_damage(attacker_guid, victim_guid, victim_health) do
    DuelManager.report_damage(attacker_guid, victim_guid, victim_health)
  end

  @doc """
  Update player position for boundary checking.
  Called by movement system during active duels.
  """
  @spec update_position(non_neg_integer(), {float(), float(), float()}) :: :ok
  def update_position(player_guid, position) do
    DuelManager.update_position(player_guid, position)
  end

  @doc """
  Check if a player is currently in an active duel.
  """
  @spec in_duel?(non_neg_integer()) :: boolean()
  def in_duel?(player_guid) do
    DuelManager.in_duel?(player_guid)
  end

  @doc """
  Check if two players are dueling each other.
  Used by combat system to allow damage between duelists.
  """
  @spec dueling_each_other?(non_neg_integer(), non_neg_integer()) :: boolean()
  def dueling_each_other?(player1_guid, player2_guid) do
    DuelManager.dueling_each_other?(player1_guid, player2_guid)
  end

  @doc """
  Build and send a duel result packet.
  """
  @spec send_duel_result(map(), [non_neg_integer()]) :: :ok
  def send_duel_result(duel, recipient_guids) do
    winner_name =
      if duel.challenger_guid == duel.winner_guid,
        do: duel.challenger_name,
        else: duel.target_name

    loser_name =
      if duel.challenger_guid == duel.loser_guid,
        do: duel.challenger_name,
        else: duel.target_name

    result_packet =
      case duel.end_reason do
        :defeat -> ServerDuelResult.victory(duel.winner_guid, winner_name, duel.loser_guid, loser_name)
        :flee -> ServerDuelResult.flee(duel.winner_guid, winner_name, duel.loser_guid, loser_name)
        :forfeit -> ServerDuelResult.forfeit(duel.winner_guid, winner_name, duel.loser_guid, loser_name)
        :timeout -> ServerDuelResult.timeout(duel.winner_guid, winner_name, duel.loser_guid, loser_name)
        _ -> ServerDuelResult.victory(duel.winner_guid, winner_name, duel.loser_guid, loser_name)
      end

    # In a real implementation, broadcast to all recipient GUIDs
    Logger.debug("Sending duel result to #{length(recipient_guids)} players")

    writer = PacketWriter.new()
    {:ok, writer} = ServerDuelResult.write(result_packet, writer)
    _packet_data = PacketWriter.to_binary(writer)

    # TODO: Route packet to recipient sessions via session registry
    :ok
  end

  # Private functions

  defp send_duel_request_to_target(challenger_guid, challenger_name, target_guid, state) do
    request_packet = ServerDuelRequest.new(challenger_guid, challenger_name, @request_timeout_seconds)

    writer = PacketWriter.new()
    {:ok, writer} = ServerDuelRequest.write(request_packet, writer)
    _packet_data = PacketWriter.to_binary(writer)

    # TODO: Route packet to target's session via session registry
    Logger.debug("Duel request notification sent to #{target_guid}")

    {:ok, state}
  end

  defp send_duel_countdown(duel, state) do
    entity_guid = state.session_data[:entity_guid]

    # Determine opponent for this player
    {opponent_guid, opponent_name} =
      if duel.challenger_guid == entity_guid do
        {duel.target_guid, duel.target_name}
      else
        {duel.challenger_guid, duel.challenger_name}
      end

    countdown_packet =
      ServerDuelCountdown.new(
        opponent_guid,
        opponent_name,
        @countdown_seconds,
        duel.center,
        duel.radius
      )

    send_packet(:server_duel_countdown, countdown_packet, state)
  end

  defp send_packet(opcode, packet, state) do
    writer = PacketWriter.new()

    {:ok, writer} =
      case opcode do
        :server_duel_request -> ServerDuelRequest.write(packet, writer)
        :server_duel_countdown -> ServerDuelCountdown.write(packet, writer)
        :server_duel_result -> ServerDuelResult.write(packet, writer)
      end

    packet_data = PacketWriter.to_binary(writer)
    {:reply, opcode, packet_data, state}
  end
end
