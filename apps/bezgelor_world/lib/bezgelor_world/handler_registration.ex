defmodule BezgelorWorld.HandlerRegistration do
  @moduledoc """
  Registers world handlers with the packet registry at application startup.

  This module breaks the compile-time dependency between bezgelor_protocol
  and bezgelor_world by registering handlers at runtime instead of hardcoding
  them in PacketRegistry's default_handlers.

  ## Why This Exists

  The protocol layer shouldn't have compile-time knowledge of world handlers.
  This allows proper layering:
  - bezgelor_protocol depends on bezgelor_db (for auth)
  - bezgelor_world depends on bezgelor_protocol (for packets)
  - No reverse dependency from protocol to world

  ## Usage

  Called automatically from `BezgelorWorld.Application.start/2` before
  the supervision tree starts.
  """

  alias BezgelorProtocol.PacketRegistry

  alias BezgelorWorld.Handler.{
    AchievementHandler,
    BattlegroundHandler,
    ChatHandler,
    CombatHandler,
    CraftingHandler,
    DuelHandler,
    EventHandler,
    GatheringHandler,
    GroupFinderHandler,
    GuildHandler,
    HousingHandler,
    InventoryHandler,
    LootHandler,
    MailHandler,
    MountHandler,
    PathHandler,
    PetHandler,
    QuestHandler,
    ReputationHandler,
    SocialHandler,
    SpellHandler,
    StorefrontHandler,
    TitleHandler,
    TradeskillHandler
  }

  @doc """
  Register all world handlers with the packet registry.

  This must be called before any packets are dispatched.
  """
  @spec register_all() :: :ok
  def register_all do
    # Chat
    PacketRegistry.register(:client_chat, ChatHandler)
    PacketRegistry.register(:client_emote, ChatHandler)

    # Spells
    PacketRegistry.register(:client_cast_spell, SpellHandler)
    PacketRegistry.register(:client_cancel_cast, SpellHandler)

    # Combat
    PacketRegistry.register(:client_set_target, CombatHandler)
    PacketRegistry.register(:client_respawn, CombatHandler)

    # Social
    PacketRegistry.register(:client_friend_add, SocialHandler)
    PacketRegistry.register(:client_friend_remove, SocialHandler)
    PacketRegistry.register(:client_ignore_add, SocialHandler)
    PacketRegistry.register(:client_ignore_remove, SocialHandler)

    # Inventory
    PacketRegistry.register(:client_swap_items, InventoryHandler)
    PacketRegistry.register(:client_split_stack, InventoryHandler)
    PacketRegistry.register(:client_delete_item, InventoryHandler)
    PacketRegistry.register(:client_use_item, InventoryHandler)

    # Quests
    PacketRegistry.register(:client_quest_accept, QuestHandler)
    PacketRegistry.register(:client_quest_abandon, QuestHandler)
    PacketRegistry.register(:client_quest_complete, QuestHandler)
    PacketRegistry.register(:client_quest_share, QuestHandler)

    # Achievements
    PacketRegistry.register(:client_achievement_track, AchievementHandler)
    PacketRegistry.register(:client_achievement_claim, AchievementHandler)

    # Paths
    PacketRegistry.register(:client_path_ability, PathHandler)
    PacketRegistry.register(:client_path_unlock, PathHandler)

    # Guilds
    PacketRegistry.register(:client_guild_create, GuildHandler)
    PacketRegistry.register(:client_guild_invite, GuildHandler)
    PacketRegistry.register(:client_guild_leave, GuildHandler)
    PacketRegistry.register(:client_guild_kick, GuildHandler)
    PacketRegistry.register(:client_guild_promote, GuildHandler)
    PacketRegistry.register(:client_guild_demote, GuildHandler)
    PacketRegistry.register(:client_guild_message, GuildHandler)
    PacketRegistry.register(:client_guild_info_request, GuildHandler)

    # Mail
    PacketRegistry.register(:client_mail_send, MailHandler)
    PacketRegistry.register(:client_mail_read, MailHandler)
    PacketRegistry.register(:client_mail_delete, MailHandler)
    PacketRegistry.register(:client_mail_take_attachment, MailHandler)
    PacketRegistry.register(:client_mail_return, MailHandler)

    # Housing
    PacketRegistry.register(:client_housing_enter, HousingHandler)
    PacketRegistry.register(:client_housing_leave, HousingHandler)
    PacketRegistry.register(:client_housing_decor_place, HousingHandler)
    PacketRegistry.register(:client_housing_decor_remove, HousingHandler)

    # Reputation
    PacketRegistry.register(:client_reputation_info, ReputationHandler)

    # Mounts
    PacketRegistry.register(:client_mount_summon, MountHandler)
    PacketRegistry.register(:client_mount_dismiss, MountHandler)
    PacketRegistry.register(:client_mount_set_favorite, MountHandler)

    # Pets
    PacketRegistry.register(:client_pet_summon, PetHandler)
    PacketRegistry.register(:client_pet_dismiss, PetHandler)
    PacketRegistry.register(:client_pet_rename, PetHandler)

    # Titles
    PacketRegistry.register(:client_set_active_title, TitleHandler)

    # Tradeskills
    PacketRegistry.register(:client_tradeskill_learn, TradeskillHandler)
    PacketRegistry.register(:client_tradeskill_unlearn, TradeskillHandler)
    PacketRegistry.register(:client_tradeskill_talent, TradeskillHandler)

    # Crafting
    PacketRegistry.register(:client_craft_start, CraftingHandler)
    PacketRegistry.register(:client_craft_cancel, CraftingHandler)
    PacketRegistry.register(:client_craft_additive, CraftingHandler)

    # Gathering
    PacketRegistry.register(:client_gather_start, GatheringHandler)
    PacketRegistry.register(:client_gather_complete, GatheringHandler)

    # Public events
    PacketRegistry.register(:client_event_join, EventHandler)
    PacketRegistry.register(:client_event_leave, EventHandler)

    # Group finder
    PacketRegistry.register(:client_group_finder_join, GroupFinderHandler)
    PacketRegistry.register(:client_group_finder_leave, GroupFinderHandler)
    PacketRegistry.register(:client_group_finder_ready, GroupFinderHandler)

    # Loot
    PacketRegistry.register(:client_loot_roll, LootHandler)
    PacketRegistry.register(:client_loot_settings, LootHandler)
    PacketRegistry.register(:client_loot_master_assign, LootHandler)
    PacketRegistry.register(:client_loot_corpse, LootHandler)

    # Duels
    PacketRegistry.register(:client_duel_request, DuelHandler)
    PacketRegistry.register(:client_duel_response, DuelHandler)
    PacketRegistry.register(:client_duel_cancel, DuelHandler)

    # Battlegrounds
    PacketRegistry.register(:client_battleground_join, BattlegroundHandler)
    PacketRegistry.register(:client_battleground_leave, BattlegroundHandler)
    PacketRegistry.register(:client_battleground_ready, BattlegroundHandler)

    # Storefront
    PacketRegistry.register(:client_store_browse, StorefrontHandler)
    PacketRegistry.register(:client_store_purchase, StorefrontHandler)
    PacketRegistry.register(:client_store_get_daily_deals, StorefrontHandler)

    :ok
  end
end
