defmodule BezgelorWorld.Handler.PetHandler do
  @moduledoc """
  Handles pet summoning, dismissing, renaming, and XP.

  ## Packets Handled
  - ClientPetSummon - Summon a pet from collection
  - ClientPetDismiss - Dismiss current pet
  - ClientPetRename - Rename active pet

  ## Packets Sent
  - ServerPetUpdate - Pet state change notification
  - ServerPetXp - XP gain notification

  ## Auto-Combat

  Pets automatically participate in combat when the player fights.
  They earn 10% of kill XP. This is a simplified system from WildStar's
  full pet ability system.
  """

  @behaviour BezgelorProtocol.Handler

  require Logger

  alias BezgelorDb.{Collections, Pets}
  alias BezgelorProtocol.PacketReader
  alias BezgelorProtocol.PacketWriter

  alias BezgelorProtocol.Packets.World.{
    ClientPetSummon,
    ClientPetDismiss,
    ClientPetRename,
    ServerPetUpdate,
    ServerPetXP
  }

  # 10% of kill XP goes to pet
  @pet_xp_share 0.10

  @impl true
  def handle(payload, state) do
    reader = PacketReader.new(payload)

    with {:error, _} <- try_summon(reader, state),
         {:error, _} <- try_dismiss(reader, state),
         {:error, _} <- try_rename(reader, state) do
      {:error, :unknown_pet_packet}
    end
  end

  # Summon pet

  defp try_summon(reader, state) do
    case ClientPetSummon.read(reader) do
      {:ok, packet, _} -> handle_summon(packet, state)
      error -> error
    end
  end

  defp handle_summon(packet, state) do
    character_id = state.session_data[:character_id]
    account_id = state.session_data[:account_id]
    entity_guid = state.session_data[:entity_guid]

    case Pets.set_active_pet(character_id, account_id, packet.pet_id) do
      {:ok, pet} ->
        Logger.debug("Character #{character_id} summoned pet #{pet.pet_id}")

        response =
          ServerPetUpdate.summoned(
            entity_guid,
            pet.pet_id,
            pet.level,
            pet.xp,
            pet.nickname
          )

        writer = PacketWriter.new()
        {:ok, writer} = ServerPetUpdate.write(response, writer)
        packet_data = PacketWriter.to_binary(writer)

        {:reply, :server_pet_update, packet_data, state,
         broadcast: {:nearby, :server_pet_update, packet_data}}

      {:error, :not_owned} ->
        Logger.warning("Character #{character_id} tried to summon unowned pet #{packet.pet_id}")
        {:ok, state}

      {:error, reason} ->
        Logger.error("Failed to summon pet: #{inspect(reason)}")
        {:ok, state}
    end
  end

  # Dismiss pet

  defp try_dismiss(reader, state) do
    case ClientPetDismiss.read(reader) do
      {:ok, _packet, _} -> handle_dismiss(state)
      error -> error
    end
  end

  defp handle_dismiss(state) do
    character_id = state.session_data[:character_id]
    entity_guid = state.session_data[:entity_guid]

    :ok = Pets.clear_active_pet(character_id)
    Logger.debug("Character #{character_id} dismissed pet")

    response = ServerPetUpdate.dismissed(entity_guid)
    writer = PacketWriter.new()
    {:ok, writer} = ServerPetUpdate.write(response, writer)
    packet_data = PacketWriter.to_binary(writer)

    {:reply, :server_pet_update, packet_data, state,
     broadcast: {:nearby, :server_pet_update, packet_data}}
  end

  # Rename pet

  defp try_rename(reader, state) do
    case ClientPetRename.read(reader) do
      {:ok, packet, _} -> handle_rename(packet, state)
      error -> error
    end
  end

  defp handle_rename(packet, state) do
    character_id = state.session_data[:character_id]
    entity_guid = state.session_data[:entity_guid]

    case Pets.set_nickname(character_id, packet.nickname) do
      {:ok, pet} ->
        Logger.debug("Character #{character_id} renamed pet to #{pet.nickname}")

        response =
          ServerPetUpdate.summoned(
            entity_guid,
            pet.pet_id,
            pet.level,
            pet.xp,
            pet.nickname
          )

        writer = PacketWriter.new()
        {:ok, writer} = ServerPetUpdate.write(response, writer)
        packet_data = PacketWriter.to_binary(writer)

        {:reply, :server_pet_update, packet_data, state}

      {:error, :no_active_pet} ->
        Logger.warning("Character #{character_id} tried to rename without active pet")
        {:ok, state}

      {:error, reason} ->
        Logger.error("Failed to rename pet: #{inspect(reason)}")
        {:ok, state}
    end
  end

  # Public API

  @doc """
  Send pet collection to client on login.
  """
  @spec send_pet_collection(pid(), integer(), integer()) :: :ok
  def send_pet_collection(connection_pid, account_id, character_id) do
    pets = Collections.get_all_pets(account_id, character_id)
    active = Pets.get_active_pet(character_id)

    # If there's an active pet, send update
    if active do
      entity_guid = get_entity_guid(connection_pid)

      response =
        ServerPetUpdate.summoned(
          entity_guid,
          active.pet_id,
          active.level,
          active.xp,
          active.nickname
        )

      writer = PacketWriter.new()
      {:ok, writer} = ServerPetUpdate.write(response, writer)
      packet_data = PacketWriter.to_binary(writer)

      send(connection_pid, {:send_packet, :server_pet_update, packet_data})
    end

    Logger.debug("Sent #{length(pets)} pets to character #{character_id}")
    :ok
  end

  @doc """
  Award XP to pet when player kills an enemy.
  Called from CombatHandler on creature kill.
  """
  @spec on_enemy_killed(pid(), integer(), integer()) :: :ok
  def on_enemy_killed(connection_pid, character_id, xp_earned) do
    pet_xp = trunc(xp_earned * @pet_xp_share)

    if pet_xp > 0 do
      case Pets.award_pet_xp(character_id, pet_xp) do
        {:ok, pet, :level_up} ->
          Logger.info("Pet leveled up to #{pet.level} for character #{character_id}")
          send_pet_xp(connection_pid, pet_xp, pet.level, pet.xp, true)

        {:ok, pet, :xp_gained} ->
          send_pet_xp(connection_pid, pet_xp, pet.level, pet.xp, false)

        {:error, :no_active_pet} ->
          :ok
      end
    end

    :ok
  end

  defp send_pet_xp(connection_pid, xp_gained, level, current_xp, leveled_up) do
    response = ServerPetXP.new(xp_gained, current_xp, level, leveled_up)

    writer = PacketWriter.new()
    {:ok, writer} = ServerPetXP.write(response, writer)
    packet_data = PacketWriter.to_binary(writer)

    send(connection_pid, {:send_packet, :server_pet_xp, packet_data})
  end

  defp get_entity_guid(_connection_pid) do
    # Would retrieve from session state
    # For now return a placeholder - real impl would query WorldManager
    0
  end
end
