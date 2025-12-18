defmodule BezgelorProtocol.ItemSlots do
  @moduledoc """
  Shared constants for item slot mappings between WildStar client and server.

  WildStar uses two different slot numbering systems:

  1. **ItemSlot** (client-side): Used in Item2Type.itemSlotId, visual updates
     - ArmorChest=1, ArmorLegs=2, ArmorHead=3, etc.
     - WeaponPrimary=20, ArmorShields=43

  2. **EquippedItem** (server/protocol): Used internally and in some packets
     - Chest=0, Legs=1, Head=2, etc.
     - WeaponPrimary=16, Shields=15

  This module provides bidirectional mappings between these systems.

  ## Usage

      # Convert ItemSlot (from client data) to EquippedItem (for storage)
      equipped = ItemSlots.item_slot_to_equipped(20)  # => 16

      # Convert EquippedItem (from storage) to ItemSlot (for visual packets)
      item_slot = ItemSlots.equipped_to_item_slot(16)  # => 20

      # Get visible equipment slots for visual updates
      ItemSlots.visible_equipment_slots()  # => [0, 1, 2, 3, 4, 5, 16]
  """

  # ItemSlot (client enum) -> EquippedItem (internal slot) mapping
  # Used when creating characters or equipping items from client data
  @item_slot_to_equipped %{
    1 => 0,    # ArmorChest -> Chest
    2 => 1,    # ArmorLegs -> Legs
    3 => 2,    # ArmorHead -> Head
    4 => 3,    # ArmorShoulder -> Shoulder
    5 => 4,    # ArmorFeet -> Feet
    6 => 5,    # ArmorHands -> Hands
    7 => 6,    # WeaponTool -> WeaponTool
    20 => 16,  # WeaponPrimary -> WeaponPrimary
    43 => 15,  # ArmorShields -> Shields
    46 => 11,  # ArmorGadget -> Gadget
    57 => 7,   # ArmorWeaponAttachment -> WeaponAttachment
    58 => 8,   # ArmorSystem -> System
    59 => 9,   # ArmorAugment -> Augment
    60 => 10   # ArmorImplant -> Implant
  }

  # EquippedItem (internal slot) -> ItemSlot (client enum) mapping
  # Used when sending visual update packets to client
  @equipped_to_item_slot %{
    0 => 1,    # Chest -> ArmorChest
    1 => 2,    # Legs -> ArmorLegs
    2 => 3,    # Head -> ArmorHead
    3 => 4,    # Shoulder -> ArmorShoulder
    4 => 5,    # Feet -> ArmorFeet
    5 => 6,    # Hands -> ArmorHands
    6 => 7,    # WeaponTool -> WeaponTool
    15 => 43,  # Shields -> ArmorShields
    16 => 20   # WeaponPrimary -> WeaponPrimary
  }

  # Visible equipment slots (EquippedItem numbers) that affect character appearance
  @visible_equipment_slots [0, 1, 2, 3, 4, 5, 16]

  @doc """
  Convert an ItemSlot (client enum) to an EquippedItem slot (internal).

  Returns nil if the ItemSlot is not mapped.
  """
  @spec item_slot_to_equipped(non_neg_integer()) :: non_neg_integer() | nil
  def item_slot_to_equipped(item_slot) do
    Map.get(@item_slot_to_equipped, item_slot)
  end

  @doc """
  Convert an EquippedItem slot (internal) to an ItemSlot (client enum).

  Falls back to the input value if not explicitly mapped.
  """
  @spec equipped_to_item_slot(non_neg_integer()) :: non_neg_integer()
  def equipped_to_item_slot(equipped_slot) do
    Map.get(@equipped_to_item_slot, equipped_slot, equipped_slot)
  end

  @doc """
  Returns the list of EquippedItem slots that are visible on the character.

  These slots affect the character's appearance and need visual updates
  when equipment changes.
  """
  @spec visible_equipment_slots() :: [non_neg_integer()]
  def visible_equipment_slots, do: @visible_equipment_slots
end
