defmodule BezgelorProtocol.Handler.MountHandler do
  @moduledoc """
  Handler for mount-related packets.

  Handles summoning, dismissing, and customizing mounts.

  ## Flow

  1. Parse mount packet
  2. Validate player is in world and owns mount
  3. Update mount state in database
  4. Return reply packets to broadcast state change
  """

  @behaviour BezgelorProtocol.Handler

  alias BezgelorProtocol.PacketReader
  alias BezgelorProtocol.PacketWriter
  alias BezgelorProtocol.Packets.World.{
    ClientMountSummon,
    ClientMountDismiss,
    ClientMountCustomize,
    ServerMountUpdate,
    ServerMountCustomization
  }
  alias BezgelorDb.Mounts

  require Logger

  @impl true
  def handle(payload, state) do
    reader = PacketReader.new(payload)
    opcode = state.current_opcode

    case opcode do
      :client_mount_summon -> handle_summon(reader, state)
      :client_mount_dismiss -> handle_dismiss(reader, state)
      :client_mount_customize -> handle_customize(reader, state)
      _ -> {:error, :unknown_mount_opcode}
    end
  end

  defp handle_summon(reader, state) do
    with {:ok, packet, _reader} <- ClientMountSummon.read(reader),
         :ok <- validate_in_world(state) do
      process_summon(packet, state)
    else
      {:error, reason} ->
        Logger.warning("Mount summon failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp handle_dismiss(reader, state) do
    with {:ok, _packet, _reader} <- ClientMountDismiss.read(reader),
         :ok <- validate_in_world(state) do
      process_dismiss(state)
    else
      {:error, reason} ->
        Logger.warning("Mount dismiss failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp handle_customize(reader, state) do
    with {:ok, packet, _reader} <- ClientMountCustomize.read(reader),
         :ok <- validate_in_world(state) do
      process_customize(packet, state)
    else
      {:error, reason} ->
        Logger.warning("Mount customize failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp validate_in_world(state) do
    if state.session_data[:in_world] do
      :ok
    else
      {:error, :not_in_world}
    end
  end

  defp process_summon(packet, state) do
    character_id = state.session_data[:character_id]
    account_id = state.session_data[:account_id]
    entity_guid = state.session_data[:entity_guid]

    case Mounts.set_active_mount(character_id, account_id, packet.mount_id) do
      {:ok, _mount} ->
        update_packet = ServerMountUpdate.mounted(entity_guid, packet.mount_id)
        {opcode, payload} = serialize_packet(update_packet)

        Logger.debug("Player #{character_id} summoned mount #{packet.mount_id}")
        {:reply, opcode, payload, state}

      {:error, :not_owned} ->
        Logger.warning("Player #{character_id} tried to summon unowned mount #{packet.mount_id}")
        {:error, :not_owned}

      {:error, reason} ->
        Logger.warning("Failed to summon mount: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp process_dismiss(state) do
    character_id = state.session_data[:character_id]
    entity_guid = state.session_data[:entity_guid]

    :ok = Mounts.clear_active_mount(character_id)

    update_packet = ServerMountUpdate.dismounted(entity_guid)
    {opcode, payload} = serialize_packet(update_packet)

    Logger.debug("Player #{character_id} dismissed mount")
    {:reply, opcode, payload, state}
  end

  defp process_customize(packet, state) do
    character_id = state.session_data[:character_id]
    entity_guid = state.session_data[:entity_guid]

    customization = %{
      "dyes" => packet.dyes,
      "flair" => packet.flairs
    }

    case Mounts.update_customization(character_id, customization) do
      {:ok, mount} ->
        custom_packet = %ServerMountCustomization{
          entity_guid: entity_guid,
          mount_id: mount.mount_id,
          dyes: packet.dyes,
          flairs: packet.flairs
        }
        {opcode, payload} = serialize_packet(custom_packet)

        Logger.debug("Player #{character_id} customized mount")
        {:reply, opcode, payload, state}

      {:error, :no_active_mount} ->
        Logger.warning("Player #{character_id} tried to customize without active mount")
        {:error, :no_active_mount}

      {:error, reason} ->
        Logger.warning("Failed to customize mount: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Serialize a packet struct to {opcode, binary_payload}
  defp serialize_packet(packet) do
    opcode = packet.__struct__.opcode()
    writer = PacketWriter.new()
    {:ok, writer} = packet.__struct__.write(packet, writer)
    payload = PacketWriter.to_binary(writer)
    {opcode, payload}
  end
end
