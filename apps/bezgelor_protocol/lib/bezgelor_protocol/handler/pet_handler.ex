defmodule BezgelorProtocol.Handler.PetHandler do
  @moduledoc """
  Handler for pet-related packets.

  Handles summoning, dismissing, renaming pets, and auto-combat XP awards.

  ## Auto-Combat System

  Pets gain XP when their owner kills enemies. The XP is calculated as a
  percentage of the enemy's base XP value. This creates a passive leveling
  system that rewards players for keeping their pets summoned during combat.

  ## Flow

  1. Parse pet packet
  2. Validate player is in world and owns pet
  3. Update pet state in database
  4. Return reply packets to sync state
  """

  @behaviour BezgelorProtocol.Handler

  alias BezgelorProtocol.PacketReader
  alias BezgelorProtocol.PacketWriter

  alias BezgelorProtocol.Packets.World.{
    ClientPetSummon,
    ClientPetDismiss,
    ClientPetRename,
    ServerPetUpdate,
    ServerPetXP
  }

  alias BezgelorDb.Pets

  require Logger

  # Percentage of enemy XP that goes to pet
  @pet_xp_share 0.25

  @impl true
  def handle(payload, state) do
    reader = PacketReader.new(payload)
    opcode = state.current_opcode

    case opcode do
      :client_pet_summon -> handle_summon(reader, state)
      :client_pet_dismiss -> handle_dismiss(reader, state)
      :client_pet_rename -> handle_rename(reader, state)
      _ -> {:error, :unknown_pet_opcode}
    end
  end

  @doc """
  Award XP to the player's active pet when combat ends.

  Called by combat system when an enemy is killed. Returns the XP packet
  to send to the player, or nil if no pet is active.

  ## Parameters
  - character_id: The character who killed the enemy
  - enemy_xp: Base XP value of the killed enemy

  ## Returns
  - `{opcode, payload}` tuple if pet gained XP
  - `nil` if no active pet
  """
  @spec award_combat_xp(integer(), integer()) :: {atom(), binary()} | nil
  def award_combat_xp(character_id, enemy_xp) do
    pet_xp = trunc(enemy_xp * @pet_xp_share)

    if pet_xp > 0 do
      case Pets.award_pet_xp(character_id, pet_xp) do
        {:ok, pet, event} ->
          leveled_up = event == :level_up
          xp_packet = ServerPetXP.new(pet_xp, pet.xp, pet.level, leveled_up)
          serialize_packet(xp_packet)

        {:error, :no_active_pet} ->
          nil

        {:error, reason} ->
          Logger.warning("Failed to award pet XP: #{inspect(reason)}")
          nil
      end
    else
      nil
    end
  end

  defp handle_summon(reader, state) do
    with {:ok, packet, _reader} <- ClientPetSummon.read(reader),
         :ok <- validate_in_world(state) do
      process_summon(packet, state)
    else
      {:error, reason} ->
        Logger.warning("Pet summon failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp handle_dismiss(reader, state) do
    with {:ok, _packet, _reader} <- ClientPetDismiss.read(reader),
         :ok <- validate_in_world(state) do
      process_dismiss(state)
    else
      {:error, reason} ->
        Logger.warning("Pet dismiss failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp handle_rename(reader, state) do
    with {:ok, packet, _reader} <- ClientPetRename.read(reader),
         :ok <- validate_in_world(state) do
      process_rename(packet, state)
    else
      {:error, reason} ->
        Logger.warning("Pet rename failed: #{inspect(reason)}")
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

    case Pets.set_active_pet(character_id, account_id, packet.pet_id) do
      {:ok, pet} ->
        update_packet =
          ServerPetUpdate.summoned(
            entity_guid,
            pet.pet_id,
            pet.level,
            pet.xp,
            pet.nickname
          )

        {opcode, payload} = serialize_packet(update_packet)

        Logger.debug("Player #{character_id} summoned pet #{packet.pet_id}")
        {:reply_world_encrypted, opcode, payload, state}

      {:error, :not_owned} ->
        Logger.warning("Player #{character_id} tried to summon unowned pet #{packet.pet_id}")
        {:error, :not_owned}

      {:error, reason} ->
        Logger.warning("Failed to summon pet: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp process_dismiss(state) do
    character_id = state.session_data[:character_id]
    entity_guid = state.session_data[:entity_guid]

    :ok = Pets.clear_active_pet(character_id)

    update_packet = ServerPetUpdate.dismissed(entity_guid)
    {opcode, payload} = serialize_packet(update_packet)

    Logger.debug("Player #{character_id} dismissed pet")
    {:reply_world_encrypted, opcode, payload, state}
  end

  defp process_rename(packet, state) do
    character_id = state.session_data[:character_id]
    entity_guid = state.session_data[:entity_guid]

    case Pets.set_nickname(character_id, packet.nickname) do
      {:ok, pet} ->
        update_packet =
          ServerPetUpdate.summoned(
            entity_guid,
            pet.pet_id,
            pet.level,
            pet.xp,
            pet.nickname
          )

        {opcode, payload} = serialize_packet(update_packet)

        Logger.debug("Player #{character_id} renamed pet to '#{packet.nickname}'")
        {:reply_world_encrypted, opcode, payload, state}

      {:error, :no_active_pet} ->
        Logger.warning("Player #{character_id} tried to rename without active pet")
        {:error, :no_active_pet}

      {:error, reason} ->
        Logger.warning("Failed to rename pet: #{inspect(reason)}")
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
