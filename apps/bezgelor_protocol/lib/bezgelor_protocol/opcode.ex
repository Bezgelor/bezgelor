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

  # Connection state opcodes (ignored)
  @client_state 0x0000

  # Auth Server Opcodes
  @server_hello 0x0003
  @client_hello_auth 0x0004
  @server_auth_accepted 0x0005
  @server_auth_denied 0x0006
  @server_auth_encrypted 0x0076
  @client_encrypted 0x0244

  # Realm Server Opcodes (port 23115)
  @client_hello_auth_realm 0x0592
  @server_auth_accepted_realm 0x0591
  @server_auth_denied_realm 0x063D
  @server_realm_messages 0x0593
  @server_realm_info 0x03DB

  # Realm List Opcodes (World Server - character select screen)
  @client_realm_list 0x07A4
  @server_realm_list 0x0761
  @client_realm_select 0x07DF
  @server_new_realm 0x0760

  # World Server Opcodes
  @server_player_entered_world 0x0061
  @client_hello_realm 0x058F
  @server_realm_encrypted 0x03DC
  @client_packed_world 0x038C
  @client_packed 0x025C
  @client_pregame_keep_alive 0x0241
  @client_storefront_request_catalog 0x082D
  @server_character_list 0x0117
  @server_max_character_level_achieved 0x0036
  @server_reward_property_set 0x092C
  @server_account_currency_set 0x0966
  @server_account_entitlements 0x0968
  @server_account_tier 0x097F
  @server_generic_unlock_account_list 0x0981
  @server_store_finalise 0x0987
  @server_store_categories 0x0988
  @server_store_offers 0x098B
  @client_character_list 0x07E0
  @client_character_select 0x07DD
  @client_character_create 0x025B
  @server_character_create 0x00DC
  @client_character_delete 0x0352
  @server_character_delete_result 0x00E6
  @client_entered_world 0x00F2
  @client_request_action_set_changes 0x00B1
  @server_action_set_clear_cache 0x00B2

  # Logout opcodes
  @server_logout_update 0x0092
  @client_logout_request 0x00BF
  @client_logout_confirm 0x00C0
  @server_logout 0x0594

  # Client statistics/telemetry opcodes
  @client_statistics_watchdog 0x023C
  @client_statistics_window_open 0x023D
  @client_statistics_gfx 0x023E
  @client_statistics_connection 0x023F
  @client_statistics_framerate 0x0240

  # Movement/Entity command opcodes
  @client_entity_command 0x0637
  @server_entity_command 0x0638
  @client_entity_select 0x0185
  @client_zone_change 0x063A
  @client_player_movement_speed_update 0x063B

  # Settings/Options opcodes
  @client_options 0x012B
  @client_request_input_key_set 0x0570
  @bi_input_key_set 0x056F

  # Marketplace/Auction opcodes
  @client_request_owned_commodity_orders 0x03EC
  @client_request_owned_item_auctions 0x03ED

  # Unknown opcodes (documented for investigation)
  # 0x0269: Sent after world entry, purpose unknown, not in NexusForever
  @client_unknown_0x0269 0x0269
  # 0x07CC: Sent periodically, purpose unknown, not in NexusForever
  @client_unknown_0x07CC 0x07CC
  # 0x00D5: Related to ServerInstanceSettings per NexusForever comments
  @client_unknown_0x00D5 0x00D5
  # 0x00DE: Not in NexusForever GameMessageOpcode.cs (gap between 0x00DD and 0x00E0).
  # Observed during ability use - possibly dash/sprint/momentum. Logged for research.
  @client_unknown_0x00DE 0x00DE
  # 0x00FB: Unknown, possibly path-related
  @client_unknown_0x00FB 0x00FB
  # 0x0635: Unknown, labeled Server0635 in NexusForever but sent by client
  @client_unknown_0x0635 0x0635
  # 0x00E3: Unknown, between datacube volume update and resurrect request
  @client_unknown_0x00E3 0x00E3
  # 0x018F: ClientP2PTradingCancelTrade - player canceling a trade
  @client_p2p_trading_cancel 0x018F
  # ServerChangeWorld in NexusForever
  @server_world_enter 0x00AD
  @server_instance_settings 0x00F1
  @server_housing_neighbors 0x0507
  @server_entity_create 0x0262
  @server_entity_destroy 0x0101
  @client_movement 0x07F4
  @server_movement 0x07F5
  @server_player_create 0x025E
  @server_movement_control 0x0636
  @server_time_of_day 0x0845
  @server_character_flags_updated 0x00FE
  @server_player_changed 0x019B
  @server_set_unit_path_type 0x08B8
  @server_path_initialise 0x06BC

  # Chat opcodes
  @client_chat 0x0300
  @server_chat 0x0301
  @server_chat_result 0x0302

  # Spell opcodes
  # 0x009A per NexusForever GameMessageOpcode.cs
  @client_cast_spell 0x009A
  @client_cast_spell_continuous 0x04DB
  @server_spell_go 0x07F4
  @server_cast_result 0x07FC
  @server_spell_finish 0x07FE
  @server_spell_start 0x07FF
  @server_spell_buff_remove 0x0813
  # Legacy spell opcodes (may not be correct)
  @server_spell_effect 0x0403
  @client_cancel_cast 0x0405
  @server_cooldown 0x0406
  @server_telegraph 0x0407

  # Target opcodes
  @client_set_target 0x0500
  @server_target_update 0x0501

  # Death/Respawn opcodes
  @server_entity_death 0x0510
  @client_respawn 0x0511
  @server_respawn 0x0512
  @server_player_death 0x0513
  @server_resurrect_offer 0x0514
  @client_resurrect_accept 0x0515
  @client_resurrect_at_bindpoint 0x0516
  @server_resurrect 0x0517

  # XP/Level opcodes
  @server_xp_gain 0x0520
  @server_level_up 0x0521

  # Achievement opcodes
  # ServerAchievementInit in NexusForever
  @server_achievement_list 0x00AE
  @server_achievement_update 0x00AF

  # Loot opcodes
  @server_loot_drop 0x0530
  @client_loot_corpse 0x0531

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

  # Buff/debuff opcodes
  @server_buff_apply 0x0620
  @server_buff_remove 0x0621
  @server_buff_update 0x0622
  @server_buff_list 0x0623

  # Housing opcodes
  @client_housing_enter 0x0700
  @server_housing_enter 0x0701
  @client_housing_exit 0x0702
  @server_housing_data 0x0703
  @client_housing_decor_place 0x0710
  @client_housing_decor_move 0x0711
  @client_housing_decor_remove 0x0712
  @server_housing_decor_update 0x0713
  @server_housing_decor_list 0x0714
  @client_housing_fabkit_install 0x0720
  @client_housing_fabkit_remove 0x0721
  @server_housing_fabkit_update 0x0722
  @server_housing_fabkit_list 0x0723
  @client_housing_neighbor_add 0x0730
  @client_housing_neighbor_remove 0x0731
  @client_housing_roommate_promote 0x0732
  @client_housing_roommate_demote 0x0733
  @server_housing_neighbor_list 0x0734

  # Guild opcodes
  @server_guild_data 0x0800
  @server_guild_member_update 0x0801
  @server_guild_result 0x0802
  @client_guild_create 0x0810
  @client_guild_invite 0x0811
  @client_guild_accept_invite 0x0812
  @client_guild_decline_invite 0x0813
  @client_guild_leave 0x0814
  @client_guild_kick 0x0815
  @client_guild_promote 0x0816
  @client_guild_demote 0x0817
  @client_guild_set_motd 0x0818
  @client_guild_disband 0x0819

  # Mail opcodes
  @server_mail_list 0x0900
  @server_mail_result 0x0901
  @server_mail_notification 0x0902
  @client_mail_send 0x0910
  @client_mail_get_inbox 0x0911
  @client_mail_read 0x0912
  @client_mail_take_attachments 0x0913
  @client_mail_take_gold 0x0914
  @client_mail_delete 0x0915
  @client_mail_return 0x0916

  # Dialogue opcodes
  @server_dialog_start 0x0357
  @server_dialog_end 0x0358
  @client_dialog_opened 0x0356
  @server_chat_npc 0x01C6

  # NPC interaction opcode
  @client_npc_interact 0x07EA

  # Quest opcodes
  @server_quest_offer 0x0351
  # ServerQuestInit in NexusForever
  @server_quest_list 0x035F

  # Ability/Action set opcodes
  @server_ability_points 0x0169
  @server_cooldown_list 0x091B
  @server_action_set 0x019D
  @server_amp_list 0x019E
  @server_ability_book 0x01A0

  # Item/Inventory opcodes
  @server_generic_error 0x0106
  @server_item_add 0x0111
  @server_item_delete 0x0148
  @server_item_move 0x0569
  @server_item_swap 0x0568
  @server_item_stack_count_update 0x017F
  @server_item_visual_update 0x0933
  @server_entity_visual_update 0x0905
  @client_item_move 0x0182
  @client_non_spell_action_set_changes 0x016A
  @client_ability_book_activate_spell 0x017A

  # Cinematic opcodes
  @server_cinematic_complete 0x0210
  @server_cinematic_actor_attach 0x0213
  @server_cinematic_camera_spline 0x0215
  @server_cinematic_transition 0x0218
  @server_cinematic_visual_effect 0x021C
  @server_cinematic_actor_visibility 0x0220
  @server_cinematic_transition_duration_set 0x0222
  @server_cinematic_visual_effect_end 0x0225
  @server_cinematic_scene 0x0227
  @server_cinematic_actor 0x0228
  @server_cinematic_text 0x022A
  @server_cinematic_show_animate 0x022E
  @server_cinematic_actor_angle 0x0230
  @server_cinematic_notify 0x0232

  # Mapping from atom to integer
  @opcode_map %{
    # Connection state (ignored)
    client_state: @client_state,
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
    # Realm List (World Server - character select screen)
    client_realm_list: @client_realm_list,
    server_realm_list: @server_realm_list,
    client_realm_select: @client_realm_select,
    server_new_realm: @server_new_realm,
    # World Server
    server_player_entered_world: @server_player_entered_world,
    client_hello_realm: @client_hello_realm,
    server_realm_encrypted: @server_realm_encrypted,
    client_packed_world: @client_packed_world,
    client_packed: @client_packed,
    client_pregame_keep_alive: @client_pregame_keep_alive,
    client_storefront_request_catalog: @client_storefront_request_catalog,
    server_character_list: @server_character_list,
    server_max_character_level_achieved: @server_max_character_level_achieved,
    server_reward_property_set: @server_reward_property_set,
    server_account_currency_set: @server_account_currency_set,
    server_account_entitlements: @server_account_entitlements,
    server_account_tier: @server_account_tier,
    server_generic_unlock_account_list: @server_generic_unlock_account_list,
    server_store_finalise: @server_store_finalise,
    server_store_categories: @server_store_categories,
    server_store_offers: @server_store_offers,
    client_character_list: @client_character_list,
    client_character_select: @client_character_select,
    client_character_create: @client_character_create,
    server_character_create: @server_character_create,
    client_character_delete: @client_character_delete,
    server_character_delete_result: @server_character_delete_result,
    client_entered_world: @client_entered_world,
    client_request_action_set_changes: @client_request_action_set_changes,
    server_action_set_clear_cache: @server_action_set_clear_cache,
    # Logout
    server_logout_update: @server_logout_update,
    client_logout_request: @client_logout_request,
    client_logout_confirm: @client_logout_confirm,
    server_logout: @server_logout,
    # Client statistics
    client_statistics_watchdog: @client_statistics_watchdog,
    client_statistics_window_open: @client_statistics_window_open,
    client_statistics_gfx: @client_statistics_gfx,
    client_statistics_connection: @client_statistics_connection,
    client_statistics_framerate: @client_statistics_framerate,
    # Movement/Entity commands
    client_entity_command: @client_entity_command,
    server_entity_command: @server_entity_command,
    client_entity_select: @client_entity_select,
    client_zone_change: @client_zone_change,
    client_player_movement_speed_update: @client_player_movement_speed_update,
    # Settings/Options
    client_options: @client_options,
    client_request_input_key_set: @client_request_input_key_set,
    bi_input_key_set: @bi_input_key_set,
    # Marketplace/Auction
    client_request_owned_commodity_orders: @client_request_owned_commodity_orders,
    client_request_owned_item_auctions: @client_request_owned_item_auctions,
    # Unknown opcodes
    client_unknown_0x0269: @client_unknown_0x0269,
    client_unknown_0x07CC: @client_unknown_0x07CC,
    client_unknown_0x00D5: @client_unknown_0x00D5,
    client_unknown_0x00DE: @client_unknown_0x00DE,
    client_unknown_0x00FB: @client_unknown_0x00FB,
    client_unknown_0x0635: @client_unknown_0x0635,
    client_unknown_0x00E3: @client_unknown_0x00E3,
    client_p2p_trading_cancel: @client_p2p_trading_cancel,
    server_world_enter: @server_world_enter,
    server_instance_settings: @server_instance_settings,
    server_housing_neighbors: @server_housing_neighbors,
    server_entity_create: @server_entity_create,
    server_entity_destroy: @server_entity_destroy,
    client_movement: @client_movement,
    server_movement: @server_movement,
    server_player_create: @server_player_create,
    server_movement_control: @server_movement_control,
    server_time_of_day: @server_time_of_day,
    server_character_flags_updated: @server_character_flags_updated,
    server_player_changed: @server_player_changed,
    server_set_unit_path_type: @server_set_unit_path_type,
    server_path_initialise: @server_path_initialise,
    # Chat
    client_chat: @client_chat,
    server_chat: @server_chat,
    server_chat_result: @server_chat_result,
    # Spells
    client_cast_spell: @client_cast_spell,
    client_cast_spell_continuous: @client_cast_spell_continuous,
    server_spell_go: @server_spell_go,
    server_cast_result: @server_cast_result,
    server_spell_finish: @server_spell_finish,
    server_spell_start: @server_spell_start,
    server_spell_buff_remove: @server_spell_buff_remove,
    server_spell_effect: @server_spell_effect,
    client_cancel_cast: @client_cancel_cast,
    server_cooldown: @server_cooldown,
    server_telegraph: @server_telegraph,
    # Targeting
    client_set_target: @client_set_target,
    server_target_update: @server_target_update,
    # Death/Respawn
    server_entity_death: @server_entity_death,
    client_respawn: @client_respawn,
    server_respawn: @server_respawn,
    server_player_death: @server_player_death,
    server_resurrect_offer: @server_resurrect_offer,
    client_resurrect_accept: @client_resurrect_accept,
    client_resurrect_at_bindpoint: @client_resurrect_at_bindpoint,
    server_resurrect: @server_resurrect,
    # XP/Level
    server_xp_gain: @server_xp_gain,
    server_level_up: @server_level_up,
    # Achievements
    server_achievement_list: @server_achievement_list,
    server_achievement_update: @server_achievement_update,
    # Loot
    server_loot_drop: @server_loot_drop,
    client_loot_corpse: @client_loot_corpse,
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
    server_pet_xp: @server_pet_xp,
    # Buffs/Debuffs
    server_buff_apply: @server_buff_apply,
    server_buff_remove: @server_buff_remove,
    server_buff_update: @server_buff_update,
    server_buff_list: @server_buff_list,
    # Housing
    client_housing_enter: @client_housing_enter,
    server_housing_enter: @server_housing_enter,
    client_housing_exit: @client_housing_exit,
    server_housing_data: @server_housing_data,
    client_housing_decor_place: @client_housing_decor_place,
    client_housing_decor_move: @client_housing_decor_move,
    client_housing_decor_remove: @client_housing_decor_remove,
    server_housing_decor_update: @server_housing_decor_update,
    server_housing_decor_list: @server_housing_decor_list,
    client_housing_fabkit_install: @client_housing_fabkit_install,
    client_housing_fabkit_remove: @client_housing_fabkit_remove,
    server_housing_fabkit_update: @server_housing_fabkit_update,
    server_housing_fabkit_list: @server_housing_fabkit_list,
    client_housing_neighbor_add: @client_housing_neighbor_add,
    client_housing_neighbor_remove: @client_housing_neighbor_remove,
    client_housing_roommate_promote: @client_housing_roommate_promote,
    client_housing_roommate_demote: @client_housing_roommate_demote,
    server_housing_neighbor_list: @server_housing_neighbor_list,
    # Guilds
    server_guild_data: @server_guild_data,
    server_guild_member_update: @server_guild_member_update,
    server_guild_result: @server_guild_result,
    client_guild_create: @client_guild_create,
    client_guild_invite: @client_guild_invite,
    client_guild_accept_invite: @client_guild_accept_invite,
    client_guild_decline_invite: @client_guild_decline_invite,
    client_guild_leave: @client_guild_leave,
    client_guild_kick: @client_guild_kick,
    client_guild_promote: @client_guild_promote,
    client_guild_demote: @client_guild_demote,
    client_guild_set_motd: @client_guild_set_motd,
    client_guild_disband: @client_guild_disband,
    # Mail
    server_mail_list: @server_mail_list,
    server_mail_result: @server_mail_result,
    server_mail_notification: @server_mail_notification,
    client_mail_send: @client_mail_send,
    client_mail_get_inbox: @client_mail_get_inbox,
    client_mail_read: @client_mail_read,
    client_mail_take_attachments: @client_mail_take_attachments,
    client_mail_take_gold: @client_mail_take_gold,
    client_mail_delete: @client_mail_delete,
    client_mail_return: @client_mail_return,
    # Dialogue
    server_dialog_start: @server_dialog_start,
    server_dialog_end: @server_dialog_end,
    client_dialog_opened: @client_dialog_opened,
    server_chat_npc: @server_chat_npc,
    # NPC interaction
    client_npc_interact: @client_npc_interact,
    # Quests
    server_quest_offer: @server_quest_offer,
    server_quest_list: @server_quest_list,
    # Abilities
    server_ability_points: @server_ability_points,
    server_cooldown_list: @server_cooldown_list,
    server_action_set: @server_action_set,
    server_amp_list: @server_amp_list,
    server_ability_book: @server_ability_book,
    # Items/Inventory
    server_generic_error: @server_generic_error,
    server_item_add: @server_item_add,
    server_item_delete: @server_item_delete,
    server_item_move: @server_item_move,
    server_item_swap: @server_item_swap,
    server_item_stack_count_update: @server_item_stack_count_update,
    server_item_visual_update: @server_item_visual_update,
    server_entity_visual_update: @server_entity_visual_update,
    client_item_move: @client_item_move,
    client_non_spell_action_set_changes: @client_non_spell_action_set_changes,
    client_ability_book_activate_spell: @client_ability_book_activate_spell,
    # Cinematics
    server_cinematic_complete: @server_cinematic_complete,
    server_cinematic_actor_attach: @server_cinematic_actor_attach,
    server_cinematic_camera_spline: @server_cinematic_camera_spline,
    server_cinematic_transition: @server_cinematic_transition,
    server_cinematic_visual_effect: @server_cinematic_visual_effect,
    server_cinematic_actor_visibility: @server_cinematic_actor_visibility,
    server_cinematic_transition_duration_set: @server_cinematic_transition_duration_set,
    server_cinematic_visual_effect_end: @server_cinematic_visual_effect_end,
    server_cinematic_scene: @server_cinematic_scene,
    server_cinematic_actor: @server_cinematic_actor,
    server_cinematic_text: @server_cinematic_text,
    server_cinematic_show_animate: @server_cinematic_show_animate,
    server_cinematic_actor_angle: @server_cinematic_actor_angle,
    server_cinematic_notify: @server_cinematic_notify
  }

  # Reverse mapping from integer to atom
  @reverse_map Map.new(@opcode_map, fn {k, v} -> {v, k} end)

  # Human-readable names
  @names %{
    client_state: "ClientState",
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
    client_realm_list: "ClientRealmList",
    server_realm_list: "ServerRealmList",
    client_realm_select: "ClientRealmSelect",
    server_new_realm: "ServerNewRealm",
    server_player_entered_world: "ServerPlayerEnteredWorld",
    client_hello_realm: "ClientHelloRealm",
    server_realm_encrypted: "ServerRealmEncrypted",
    client_packed_world: "ClientPackedWorld",
    client_packed: "ClientPacked",
    client_pregame_keep_alive: "ClientPregameKeepAlive",
    client_storefront_request_catalog: "ClientStorefrontRequestCatalog",
    server_character_list: "ServerCharacterList",
    server_max_character_level_achieved: "ServerMaxCharacterLevelAchieved",
    server_reward_property_set: "ServerRewardPropertySet",
    server_account_currency_set: "ServerAccountCurrencySet",
    server_account_entitlements: "ServerAccountEntitlements",
    server_account_tier: "ServerAccountTier",
    server_generic_unlock_account_list: "ServerGenericUnlockAccountList",
    server_store_finalise: "ServerStoreFinalise",
    server_store_categories: "ServerStoreCategories",
    server_store_offers: "ServerStoreOffers",
    client_character_select: "ClientCharacterSelect",
    client_character_create: "ClientCharacterCreate",
    server_character_create: "ServerCharacterCreate",
    client_character_delete: "ClientCharacterDelete",
    server_character_delete_result: "ServerCharacterDeleteResult",
    client_entered_world: "ClientEnteredWorld",
    client_request_action_set_changes: "ClientRequestActionSetChanges",
    server_action_set_clear_cache: "ServerActionSetClearCache",
    server_logout_update: "ServerLogoutUpdate",
    client_logout_request: "ClientLogoutRequest",
    client_logout_confirm: "ClientLogoutConfirm",
    server_logout: "ServerLogout",
    client_statistics_watchdog: "ClientStatisticsWatchdog",
    client_statistics_window_open: "ClientStatisticsWindowOpen",
    client_statistics_gfx: "ClientStatisticsGfx",
    client_statistics_connection: "ClientStatisticsConnection",
    client_statistics_framerate: "ClientStatisticsFramerate",
    # Movement/Entity commands
    client_entity_command: "ClientEntityCommand",
    server_entity_command: "ServerEntityCommand",
    client_entity_select: "ClientEntitySelect",
    client_zone_change: "ClientZoneChange",
    client_player_movement_speed_update: "ClientPlayerMovementSpeedUpdate",
    # Settings/Options
    client_options: "ClientOptions",
    client_request_input_key_set: "ClientRequestInputKeySet",
    bi_input_key_set: "BiInputKeySet",
    # Marketplace/Auction
    client_request_owned_commodity_orders: "ClientRequestOwnedCommodityOrders",
    client_request_owned_item_auctions: "ClientRequestOwnedItemAuctions",
    # Unknown opcodes
    client_unknown_0x0269: "ClientUnknown0x0269",
    client_unknown_0x07CC: "ClientUnknown0x07CC",
    client_unknown_0x00D5: "ClientUnknown0x00D5",
    client_unknown_0x00DE: "ClientUnknown0x00DE",
    client_unknown_0x00FB: "ClientUnknown0x00FB",
    client_unknown_0x0635: "ClientUnknown0x0635",
    client_p2p_trading_cancel: "ClientP2PTradingCancel",
    server_world_enter: "ServerWorldEnter",
    server_instance_settings: "ServerInstanceSettings",
    server_housing_neighbors: "ServerHousingNeighbors",
    server_entity_create: "ServerEntityCreate",
    server_entity_destroy: "ServerEntityDestroy",
    client_movement: "ClientMovement",
    server_movement: "ServerMovement",
    server_player_create: "ServerPlayerCreate",
    server_movement_control: "ServerMovementControl",
    server_time_of_day: "ServerTimeOfDay",
    server_character_flags_updated: "ServerCharacterFlagsUpdated",
    server_player_changed: "ServerPlayerChanged",
    server_set_unit_path_type: "ServerSetUnitPathType",
    server_path_initialise: "ServerPathInitialise",
    client_chat: "ClientChat",
    server_chat: "ServerChat",
    server_chat_result: "ServerChatResult",
    client_cast_spell: "ClientCastSpell",
    client_cast_spell_continuous: "ClientCastSpellContinuous",
    server_spell_go: "ServerSpellGo",
    server_cast_result: "ServerCastResult",
    server_spell_finish: "ServerSpellFinish",
    server_spell_start: "ServerSpellStart",
    server_spell_buff_remove: "ServerSpellBuffRemove",
    server_spell_effect: "ServerSpellEffect",
    client_cancel_cast: "ClientCancelCast",
    server_cooldown: "ServerCooldown",
    server_telegraph: "ServerTelegraph",
    client_set_target: "ClientSetTarget",
    server_target_update: "ServerTargetUpdate",
    server_entity_death: "ServerEntityDeath",
    client_respawn: "ClientRespawn",
    server_respawn: "ServerRespawn",
    server_player_death: "ServerPlayerDeath",
    server_resurrect_offer: "ServerResurrectOffer",
    client_resurrect_accept: "ClientResurrectAccept",
    client_resurrect_at_bindpoint: "ClientResurrectAtBindpoint",
    server_resurrect: "ServerResurrect",
    server_xp_gain: "ServerXPGain",
    server_level_up: "ServerLevelUp",
    server_achievement_list: "ServerAchievementList",
    server_achievement_update: "ServerAchievementUpdate",
    server_loot_drop: "ServerLootDrop",
    client_loot_corpse: "ClientLootCorpse",
    client_mount_summon: "ClientMountSummon",
    client_mount_dismiss: "ClientMountDismiss",
    server_mount_update: "ServerMountUpdate",
    client_mount_customize: "ClientMountCustomize",
    server_mount_customization: "ServerMountCustomization",
    client_pet_summon: "ClientPetSummon",
    client_pet_dismiss: "ClientPetDismiss",
    server_pet_update: "ServerPetUpdate",
    client_pet_rename: "ClientPetRename",
    server_pet_xp: "ServerPetXP",
    server_buff_apply: "ServerBuffApply",
    server_buff_remove: "ServerBuffRemove",
    server_buff_update: "ServerBuffUpdate",
    server_buff_list: "ServerBuffList",
    # Housing
    client_housing_enter: "ClientHousingEnter",
    server_housing_enter: "ServerHousingEnter",
    client_housing_exit: "ClientHousingExit",
    server_housing_data: "ServerHousingData",
    client_housing_decor_place: "ClientHousingDecorPlace",
    client_housing_decor_move: "ClientHousingDecorMove",
    client_housing_decor_remove: "ClientHousingDecorRemove",
    server_housing_decor_update: "ServerHousingDecorUpdate",
    server_housing_decor_list: "ServerHousingDecorList",
    client_housing_fabkit_install: "ClientHousingFabkitInstall",
    client_housing_fabkit_remove: "ClientHousingFabkitRemove",
    server_housing_fabkit_update: "ServerHousingFabkitUpdate",
    server_housing_fabkit_list: "ServerHousingFabkitList",
    client_housing_neighbor_add: "ClientHousingNeighborAdd",
    client_housing_neighbor_remove: "ClientHousingNeighborRemove",
    client_housing_roommate_promote: "ClientHousingRoommatePromote",
    client_housing_roommate_demote: "ClientHousingRoommateDemote",
    server_housing_neighbor_list: "ServerHousingNeighborList",
    # Guilds
    server_guild_data: "ServerGuildData",
    server_guild_member_update: "ServerGuildMemberUpdate",
    server_guild_result: "ServerGuildResult",
    client_guild_create: "ClientGuildCreate",
    client_guild_invite: "ClientGuildInvite",
    client_guild_accept_invite: "ClientGuildAcceptInvite",
    client_guild_decline_invite: "ClientGuildDeclineInvite",
    client_guild_leave: "ClientGuildLeave",
    client_guild_kick: "ClientGuildKick",
    client_guild_promote: "ClientGuildPromote",
    client_guild_demote: "ClientGuildDemote",
    client_guild_set_motd: "ClientGuildSetMotd",
    client_guild_disband: "ClientGuildDisband",
    # Mail
    server_mail_list: "ServerMailList",
    server_mail_result: "ServerMailResult",
    server_mail_notification: "ServerMailNotification",
    client_mail_send: "ClientMailSend",
    client_mail_get_inbox: "ClientMailGetInbox",
    client_mail_read: "ClientMailRead",
    client_mail_take_attachments: "ClientMailTakeAttachments",
    client_mail_take_gold: "ClientMailTakeGold",
    client_mail_delete: "ClientMailDelete",
    client_mail_return: "ClientMailReturn",
    # Dialogue
    server_dialog_start: "ServerDialogStart",
    server_dialog_end: "ServerDialogEnd",
    client_dialog_opened: "ClientDialogOpened",
    server_chat_npc: "ServerChatNPC",
    # NPC interaction
    client_npc_interact: "ClientNpcInteract",
    # Quests
    server_quest_offer: "ServerQuestOffer",
    server_quest_list: "ServerQuestList",
    # Abilities
    server_ability_points: "ServerAbilityPoints",
    server_cooldown_list: "ServerCooldownList",
    server_action_set: "ServerActionSet",
    server_amp_list: "ServerAmpList",
    server_ability_book: "ServerAbilityBook",
    # Items/Inventory
    server_generic_error: "ServerGenericError",
    server_item_add: "ServerItemAdd",
    server_item_delete: "ServerItemDelete",
    server_item_move: "ServerItemMove",
    server_item_swap: "ServerItemSwap",
    server_item_stack_count_update: "ServerItemStackCountUpdate",
    server_item_visual_update: "ServerItemVisualUpdate",
    server_entity_visual_update: "ServerEntityVisualUpdate",
    client_item_move: "ClientItemMove",
    client_non_spell_action_set_changes: "ClientNonSpellActionSetChanges",
    client_ability_book_activate_spell: "ClientAbilityBookActivateSpell",
    # Cinematics
    server_cinematic_complete: "ServerCinematicComplete",
    server_cinematic_actor_attach: "ServerCinematicActorAttach",
    server_cinematic_camera_spline: "ServerCinematicCameraSpline",
    server_cinematic_transition: "ServerCinematicTransition",
    server_cinematic_visual_effect: "ServerCinematicVisualEffect",
    server_cinematic_actor_visibility: "ServerCinematicActorVisibility",
    server_cinematic_transition_duration_set: "ServerCinematicTransitionDurationSet",
    server_cinematic_visual_effect_end: "ServerCinematicVisualEffectEnd",
    server_cinematic_scene: "ServerCinematicScene",
    server_cinematic_actor: "ServerCinematicActor",
    server_cinematic_text: "ServerCinematicText",
    server_cinematic_show_animate: "ServerCinematicShowAnimate",
    server_cinematic_actor_angle: "ServerCinematicActorAngle",
    server_cinematic_notify: "ServerCinematicNotify"
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
