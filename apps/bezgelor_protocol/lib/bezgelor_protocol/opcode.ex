defmodule BezgelorProtocol.Opcode do
  @moduledoc """
  WildStar game message opcodes.

  ## Overview

  Opcodes are 16-bit identifiers for packet types. This module provides
  bidirectional mapping between atom names and integer values.

  The opcodes are derived from NexusForever's GameMessageOpcode enum.
  We define only the opcodes we need, adding more as we implement handlers.

  ## Usage

      iex> Opcode.to_integer(:server_hello)
      3

      iex> Opcode.from_integer(0x0003)
      {:ok, :server_hello}
  """

  # Auth Server Opcodes
  @server_hello 0x0003
  @client_hello_auth 0x0004
  @server_auth_accepted 0x0005
  @server_auth_denied 0x0006
  @server_auth_encrypted 0x0076
  @client_encrypted 0x0077

  # Realm Server Opcodes (port 23115)
  @client_hello_auth_realm 0x0592
  @server_auth_accepted_realm 0x0591
  @server_auth_denied_realm 0x063D
  @server_realm_messages 0x0593
  @server_realm_info 0x03DB

  # World Server Opcodes
  @client_hello_realm 0x0008
  @server_realm_encrypted 0x0079
  @server_character_list 0x0117
  @client_character_select 0x0118
  @client_character_create 0x011A
  @server_character_create 0x011B
  @client_character_delete 0x011C
  @client_entered_world 0x00F2
  @server_world_enter 0x00F3
  @server_entity_create 0x0100
  @server_entity_destroy 0x0101
  @client_movement 0x07F4
  @server_movement 0x07F5

  # Chat opcodes
  @client_chat 0x0300
  @server_chat 0x0301
  @server_chat_result 0x0302

  # Spell opcodes
  @client_cast_spell 0x0400
  @server_spell_start 0x0401
  @server_spell_finish 0x0402
  @server_spell_effect 0x0403
  @server_cast_result 0x0404
  @client_cancel_cast 0x0405
  @server_cooldown 0x0406

  # Target opcodes
  @client_set_target 0x0500
  @server_target_update 0x0501

  # Death/Respawn opcodes
  @server_entity_death 0x0510
  @client_respawn 0x0511
  @server_respawn 0x0512

  # XP/Level opcodes
  @server_xp_gain 0x0520
  @server_level_up 0x0521

  # Loot opcodes
  @server_loot_drop 0x0530

  # Mount opcodes
  @client_mount_summon 0x0600
  @client_mount_dismiss 0x0601
  @server_mount_update 0x0602
  @client_mount_customize 0x0603
  @server_mount_customization 0x0604

  # Pet opcodes
  @client_pet_summon 0x0610
  @client_pet_dismiss 0x0611
  @server_pet_update 0x0612
  @client_pet_rename 0x0613
  @server_pet_xp 0x0614

  # Mapping from atom to integer
  @opcode_map %{
    # Auth (STS Server - port 6600)
    server_hello: @server_hello,
    client_hello_auth: @client_hello_auth,
    server_auth_accepted: @server_auth_accepted,
    server_auth_denied: @server_auth_denied,
    server_auth_encrypted: @server_auth_encrypted,
    client_encrypted: @client_encrypted,
    # Realm Server (port 23115)
    client_hello_auth_realm: @client_hello_auth_realm,
    server_auth_accepted_realm: @server_auth_accepted_realm,
    server_auth_denied_realm: @server_auth_denied_realm,
    server_realm_messages: @server_realm_messages,
    server_realm_info: @server_realm_info,
    # World Server
    client_hello_realm: @client_hello_realm,
    server_realm_encrypted: @server_realm_encrypted,
    server_character_list: @server_character_list,
    client_character_select: @client_character_select,
    client_character_create: @client_character_create,
    server_character_create: @server_character_create,
    client_character_delete: @client_character_delete,
    client_entered_world: @client_entered_world,
    server_world_enter: @server_world_enter,
    server_entity_create: @server_entity_create,
    server_entity_destroy: @server_entity_destroy,
    client_movement: @client_movement,
    server_movement: @server_movement,
    # Chat
    client_chat: @client_chat,
    server_chat: @server_chat,
    server_chat_result: @server_chat_result,
    # Spells
    client_cast_spell: @client_cast_spell,
    server_spell_start: @server_spell_start,
    server_spell_finish: @server_spell_finish,
    server_spell_effect: @server_spell_effect,
    server_cast_result: @server_cast_result,
    client_cancel_cast: @client_cancel_cast,
    server_cooldown: @server_cooldown,
    # Targeting
    client_set_target: @client_set_target,
    server_target_update: @server_target_update,
    # Death/Respawn
    server_entity_death: @server_entity_death,
    client_respawn: @client_respawn,
    server_respawn: @server_respawn,
    # XP/Level
    server_xp_gain: @server_xp_gain,
    server_level_up: @server_level_up,
    # Loot
    server_loot_drop: @server_loot_drop,
    # Mounts
    client_mount_summon: @client_mount_summon,
    client_mount_dismiss: @client_mount_dismiss,
    server_mount_update: @server_mount_update,
    client_mount_customize: @client_mount_customize,
    server_mount_customization: @server_mount_customization,
    # Pets
    client_pet_summon: @client_pet_summon,
    client_pet_dismiss: @client_pet_dismiss,
    server_pet_update: @server_pet_update,
    client_pet_rename: @client_pet_rename,
    server_pet_xp: @server_pet_xp
  }

  # Reverse mapping from integer to atom
  @reverse_map Map.new(@opcode_map, fn {k, v} -> {v, k} end)

  # Human-readable names
  @names %{
    server_hello: "ServerHello",
    client_hello_auth: "ClientHelloAuth",
    server_auth_accepted: "ServerAuthAccepted",
    server_auth_denied: "ServerAuthDenied",
    server_auth_encrypted: "ServerAuthEncrypted",
    client_encrypted: "ClientEncrypted",
    client_hello_auth_realm: "ClientHelloAuthRealm",
    server_auth_accepted_realm: "ServerAuthAcceptedRealm",
    server_auth_denied_realm: "ServerAuthDeniedRealm",
    server_realm_messages: "ServerRealmMessages",
    server_realm_info: "ServerRealmInfo",
    client_hello_realm: "ClientHelloRealm",
    server_realm_encrypted: "ServerRealmEncrypted",
    server_character_list: "ServerCharacterList",
    client_character_select: "ClientCharacterSelect",
    client_character_create: "ClientCharacterCreate",
    server_character_create: "ServerCharacterCreate",
    client_character_delete: "ClientCharacterDelete",
    client_entered_world: "ClientEnteredWorld",
    server_world_enter: "ServerWorldEnter",
    server_entity_create: "ServerEntityCreate",
    server_entity_destroy: "ServerEntityDestroy",
    client_movement: "ClientMovement",
    server_movement: "ServerMovement",
    client_chat: "ClientChat",
    server_chat: "ServerChat",
    server_chat_result: "ServerChatResult",
    client_cast_spell: "ClientCastSpell",
    server_spell_start: "ServerSpellStart",
    server_spell_finish: "ServerSpellFinish",
    server_spell_effect: "ServerSpellEffect",
    server_cast_result: "ServerCastResult",
    client_cancel_cast: "ClientCancelCast",
    server_cooldown: "ServerCooldown",
    client_set_target: "ClientSetTarget",
    server_target_update: "ServerTargetUpdate",
    server_entity_death: "ServerEntityDeath",
    client_respawn: "ClientRespawn",
    server_respawn: "ServerRespawn",
    server_xp_gain: "ServerXPGain",
    server_level_up: "ServerLevelUp",
    server_loot_drop: "ServerLootDrop",
    client_mount_summon: "ClientMountSummon",
    client_mount_dismiss: "ClientMountDismiss",
    server_mount_update: "ServerMountUpdate",
    client_mount_customize: "ClientMountCustomize",
    server_mount_customization: "ServerMountCustomization",
    client_pet_summon: "ClientPetSummon",
    client_pet_dismiss: "ClientPetDismiss",
    server_pet_update: "ServerPetUpdate",
    client_pet_rename: "ClientPetRename",
    server_pet_xp: "ServerPetXP"
  }

  @type t :: atom()

  @doc "Convert opcode atom to integer value."
  @spec to_integer(t()) :: non_neg_integer()
  def to_integer(opcode) when is_atom(opcode) do
    Map.fetch!(@opcode_map, opcode)
  end

  @doc "Convert integer to opcode atom."
  @spec from_integer(non_neg_integer()) :: {:ok, t()} | {:error, :unknown_opcode}
  def from_integer(value) when is_integer(value) do
    case Map.fetch(@reverse_map, value) do
      {:ok, opcode} -> {:ok, opcode}
      :error -> {:error, :unknown_opcode}
    end
  end

  @doc "Get human-readable name for opcode."
  @spec name(t()) :: String.t()
  def name(opcode) when is_atom(opcode) do
    Map.get(@names, opcode, Atom.to_string(opcode))
  end

  @doc "List all known opcodes."
  @spec all() :: [t()]
  def all, do: Map.keys(@opcode_map)
end
