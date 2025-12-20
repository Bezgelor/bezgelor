# Ability Bar Troubleshooting

This note captures common causes of empty or placeholder LAS slots (e.g., wavy icon on mousedown)
and the fixes that align with NexusForever behavior.

## Symptoms

- Slot R shows the default action, but slots 1-3 are blank or show a placeholder icon.
- Action set packets appear to be sent, but icons never resolve.

## Checklist

1. ServerItemAdd packets are complete (bitstream flushed)
   - The client will ignore truncated ability item packets.
   - Ensure `ServerItemAdd` calls `PacketWriter.flush_bits/1` at the end.

2. Ability inventory location matches NexusForever
   - Use `InventoryLocation.Ability = 4` (9-bit enum) for ability items and action set locations.
   - Avoid ad-hoc numeric enums that do not match retail values.

3. Ability items are sent before the action set and ability book
   - Send ability inventory (ServerItemAdd) first so action set shortcuts can resolve icons.
   - Then send ServerAbilityBook, ServerAbilityPoints, ServerActionSet, ServerAmpList, ServerCooldownList.

4. Action set locations align with ability inventory bag indices
   - For `ShortcutType.SpellbookItem`, send `Location = Ability` and `BagIndex = UILocation`.
   - Ensure the ability inventory item `bag_index` matches the action set `BagIndex`.

5. Spell IDs used are Spell4Base IDs (not Spell4 IDs)
   - Action set shortcuts and ability book entries use Spell4Base IDs.
   - If you use Spell4 IDs, icons and tiers will not resolve.

6. Ability book spec entries match NexusForever (class abilities only)
   - SpellType 5 spells should be emitted for every spec index.
   - Non-class spells should only emit spec_index=0 entries.

7. Ability items exist in the database
   - Ability items live in `inventory_items` with `container_type = :ability` and `slot = 0`.
   - If persistent data is mismatched, update `bag_index` to match slots.

## NexusForever reference

- Action set sends `InventoryLocation.Ability` for spellbook shortcuts.
- Ability items are created as Spell4Base items and sent before ability book/action set.
- Action set uses the shortcut UI location as the ability bag index.

## Quick verification steps

- Confirm `ServerItemAdd` emits valid packets (length, no truncation).
- Log ability items and action set entries for the active spec and verify bag indices line up.
- Compare with NexusForever: ability items -> ability book -> action set -> amp list -> cooldown list.
