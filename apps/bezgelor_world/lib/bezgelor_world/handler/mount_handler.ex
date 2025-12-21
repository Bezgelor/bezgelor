defmodule BezgelorWorld.Handler.MountHandler do
  @moduledoc """
  Handles mount summoning, dismissing, and customization.

  ## Packets Handled
  - ClientMountSummon - Summon a mount from collection
  - ClientMountDismiss - Dismiss current mount
  - ClientMountCustomize - Update mount customization

  ## Packets Sent
  - ServerMountUpdate - Mount state change notification
  - ServerMountCustomization - Customization update response
  """

  @behaviour BezgelorProtocol.Handler

  require Logger

  alias BezgelorDb.{Collections, Mounts}
  alias BezgelorProtocol.PacketReader
  alias BezgelorProtocol.PacketWriter

  alias BezgelorProtocol.Packets.World.{
    ClientMountSummon,
    ClientMountDismiss,
    ClientMountCustomize,
    ServerMountUpdate,
    ServerMountCustomization
  }

  @impl true
  def handle(payload, state) do
    reader = PacketReader.new(payload)

    with {:error, _} <- try_summon(reader, state),
         {:error, _} <- try_dismiss(reader, state),
         {:error, _} <- try_customize(reader, state) do
      {:error, :unknown_mount_packet}
    end
  end

  # Summon mount

  defp try_summon(reader, state) do
    case ClientMountSummon.read(reader) do
      {:ok, packet, _} -> handle_summon(packet, state)
      error -> error
    end
  end

  defp handle_summon(packet, state) do
    character_id = state.session_data[:character_id]
    account_id = state.session_data[:account_id]
    entity_guid = state.session_data[:entity_guid]

    case Mounts.set_active_mount(character_id, account_id, packet.mount_id) do
      {:ok, mount} ->
        Logger.debug("Character #{character_id} summoned mount #{mount.mount_id}")

        response = ServerMountUpdate.mounted(entity_guid, mount.mount_id)
        writer = PacketWriter.new()
        {:ok, writer} = ServerMountUpdate.write(response, writer)
        packet_data = PacketWriter.to_binary(writer)

        # Send to self and broadcast to nearby
        {:reply, :server_mount_update, packet_data, state,
         broadcast: {:nearby, :server_mount_update, packet_data}}

      {:error, :not_owned} ->
        Logger.warning(
          "Character #{character_id} tried to summon unowned mount #{packet.mount_id}"
        )

        {:ok, state}

      {:error, reason} ->
        Logger.error("Failed to summon mount: #{inspect(reason)}")
        {:ok, state}
    end
  end

  # Dismiss mount

  defp try_dismiss(reader, state) do
    case ClientMountDismiss.read(reader) do
      {:ok, _packet, _} -> handle_dismiss(state)
      error -> error
    end
  end

  defp handle_dismiss(state) do
    character_id = state.session_data[:character_id]
    entity_guid = state.session_data[:entity_guid]

    :ok = Mounts.clear_active_mount(character_id)
    Logger.debug("Character #{character_id} dismissed mount")

    response = ServerMountUpdate.dismounted(entity_guid)
    writer = PacketWriter.new()
    {:ok, writer} = ServerMountUpdate.write(response, writer)
    packet_data = PacketWriter.to_binary(writer)

    {:reply, :server_mount_update, packet_data, state,
     broadcast: {:nearby, :server_mount_update, packet_data}}
  end

  # Customize mount

  defp try_customize(reader, state) do
    case ClientMountCustomize.read(reader) do
      {:ok, packet, _} -> handle_customize(packet, state)
      error -> error
    end
  end

  defp handle_customize(packet, state) do
    character_id = state.session_data[:character_id]
    entity_guid = state.session_data[:entity_guid]

    # Convert packet fields to customization map for storage
    customization = %{
      "dyes" => packet.dyes,
      "flairs" => packet.flairs
    }

    case Mounts.update_customization(character_id, customization) do
      {:ok, mount} ->
        Logger.debug("Character #{character_id} customized mount")

        # Extract dyes/flairs from stored customization
        stored = mount.customization || %{}
        dyes = Map.get(stored, "dyes", [])
        flairs = Map.get(stored, "flairs", [])

        response = %ServerMountCustomization{
          entity_guid: entity_guid,
          mount_id: mount.mount_id,
          dyes: dyes,
          flairs: flairs
        }

        writer = PacketWriter.new()
        {:ok, writer} = ServerMountCustomization.write(response, writer)
        packet_data = PacketWriter.to_binary(writer)

        {:reply, :server_mount_customization, packet_data, state}

      {:error, :no_active_mount} ->
        Logger.warning("Character #{character_id} tried to customize without active mount")
        {:ok, state}

      {:error, reason} ->
        Logger.error("Failed to customize mount: #{inspect(reason)}")
        {:ok, state}
    end
  end

  # Public API for login/world entry

  @doc """
  Send mount collection to client on login.
  """
  @spec send_mount_collection(pid(), integer(), integer()) :: :ok
  def send_mount_collection(connection_pid, account_id, character_id) do
    mounts = Collections.get_all_mounts(account_id, character_id)
    active = Mounts.get_active_mount(character_id)

    # Would send a collection list packet here
    # For now, if there's an active mount, send update
    if active do
      entity_guid = get_entity_guid(connection_pid)

      response = ServerMountUpdate.mounted(entity_guid, active.mount_id)
      writer = PacketWriter.new()
      {:ok, writer} = ServerMountUpdate.write(response, writer)
      packet_data = PacketWriter.to_binary(writer)

      send(connection_pid, {:send_packet, :server_mount_update, packet_data})
    end

    Logger.debug("Sent #{length(mounts)} mounts to character #{character_id}")
    :ok
  end

  defp get_entity_guid(_connection_pid) do
    # Would retrieve from session state
    # For now return a placeholder - real impl would query WorldManager
    0
  end
end
