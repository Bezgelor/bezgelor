defmodule BezgelorProtocol.Handler.CharacterListHandler do
  @moduledoc """
  Handler for ClientCharacterList packets on the world server.

  This handler is called when the client requests the character list
  after connecting to the world server.

  ## Response Packets

  Sends the following packets in order:
  1. ServerAccountCurrencySet (currencies like NCoins)
  2. ServerGenericUnlockAccountList (account-wide unlocks)
  3. ServerAccountEntitlements
  4. ServerAccountTier
  5. ServerMaxCharacterLevelAchieved
  6. ServerCharacterList
  """

  @behaviour BezgelorProtocol.Handler

  alias BezgelorProtocol.Packets.World.{
    ClientCharacterList,
    ServerAccountCurrencySet,
    ServerGenericUnlockAccountList,
    ServerAccountEntitlements,
    ServerAccountTier,
    ServerRewardPropertySet,
    ServerMaxCharacterLevelAchieved,
    ServerCharacterList
  }

  alias BezgelorProtocol.{PacketReader, PacketWriter}
  alias BezgelorProtocol.Packets.World.ServerCharacterList.ItemVisual
  alias BezgelorDb.{Authorization, Characters, Inventory}

  require Logger

  @impl true
  def handle(payload, state) do
    reader = PacketReader.new(payload)

    {:ok, _packet, _reader} = ClientCharacterList.read(reader)
    send_character_list(state)
  end

  defp send_character_list(state) do
    # Get account_id from session data (set by WorldAuthHandler)
    account_id = get_in(state.session_data, [:account_id])
    realm_id = Application.get_env(:bezgelor_realm, :realm_id, 1)

    if is_nil(account_id) do
      Logger.warning("CharacterListHandler: No account_id in session")
      {:error, :not_authenticated}
    else
      # Filter characters to only show those on the current realm
      characters = Characters.list_characters(account_id, realm_id)

      # Calculate max level achieved across all characters
      # Always report at least level 50 to unlock all character creation options
      # (Veteran requires level 3+, Level50 start requires level 50)
      actual_max =
        characters
        |> Enum.map(& &1.level)
        |> Enum.max(fn -> 1 end)

      max_level = max(actual_max, 50)

      # Determine account tier based on signature permission
      has_signature = Authorization.has_permission?(account_id, "account.signature")
      account_tier = if has_signature, do: 1, else: 0

      # Signature tier gets 12 slots, free tier gets 2
      total_slots = if has_signature, do: 12, else: 2
      remaining_slots = max(0, total_slots - length(characters))

      # Build all the pre-character-list packets
      currency_set = %ServerAccountCurrencySet{currencies: []}
      unlock_list = %ServerGenericUnlockAccountList{unlock_ids: []}

      # EntitlementType.BaseCharacterSlots = 12
      # Client adds entitlement value to base 2 slots, so send (total - 2)
      entitlement_slots = max(0, total_slots - 2)

      entitlements = %ServerAccountEntitlements{
        entitlements: [
          %ServerAccountEntitlements.Entitlement{type: 12, count: entitlement_slots}
        ]
      }

      tier = %ServerAccountTier{tier: account_tier}
      reward_properties = ServerRewardPropertySet.with_character_slots(total_slots)
      max_level_packet = %ServerMaxCharacterLevelAchieved{level: max_level}

      # Build gear visuals for each character
      gear_by_character =
        characters
        |> Enum.map(fn char -> {char.id, get_gear_visuals(char.id, char.class)} end)
        |> Map.new()

      character_list = ServerCharacterList.from_characters(characters, remaining_slots, %{gear: gear_by_character})

      # Send all packets as encrypted world packets
      responses = [
        {:server_account_currency_set, encode_packet(currency_set)},
        {:server_generic_unlock_account_list, encode_packet(unlock_list)},
        {:server_account_entitlements, encode_packet(entitlements)},
        {:server_account_tier, encode_packet(tier)},
        {:server_reward_property_set, encode_packet(reward_properties)},
        {:server_max_character_level_achieved, encode_packet(max_level_packet)},
        {:server_character_list, encode_packet(character_list)}
      ]

      {:reply_multi_world_encrypted, responses, state}
    end
  end

  defp encode_packet(%ServerAccountCurrencySet{} = packet) do
    writer = PacketWriter.new()
    {:ok, writer} = ServerAccountCurrencySet.write(packet, writer)
    PacketWriter.to_binary(writer)
  end

  defp encode_packet(%ServerGenericUnlockAccountList{} = packet) do
    writer = PacketWriter.new()
    {:ok, writer} = ServerGenericUnlockAccountList.write(packet, writer)
    PacketWriter.to_binary(writer)
  end

  defp encode_packet(%ServerAccountEntitlements{} = packet) do
    writer = PacketWriter.new()
    {:ok, writer} = ServerAccountEntitlements.write(packet, writer)
    PacketWriter.to_binary(writer)
  end

  defp encode_packet(%ServerAccountTier{} = packet) do
    writer = PacketWriter.new()
    {:ok, writer} = ServerAccountTier.write(packet, writer)
    PacketWriter.to_binary(writer)
  end

  defp encode_packet(%ServerRewardPropertySet{} = packet) do
    writer = PacketWriter.new()
    {:ok, writer} = ServerRewardPropertySet.write(packet, writer)
    PacketWriter.to_binary(writer)
  end

  defp encode_packet(%ServerMaxCharacterLevelAchieved{} = packet) do
    writer = PacketWriter.new()
    {:ok, writer} = ServerMaxCharacterLevelAchieved.write(packet, writer)
    PacketWriter.to_binary(writer)
  end

  defp encode_packet(%ServerCharacterList{} = packet) do
    writer = PacketWriter.new()
    {:ok, writer} = ServerCharacterList.write(packet, writer)
    PacketWriter.to_binary(writer)
  end

  # Get gear visuals for a character from their equipped inventory items
  # Falls back to class default visuals if inventory items have no display_id
  defp get_gear_visuals(character_id, class_id) do
    # Get all equipped items for this character
    equipped_items = Inventory.get_items(character_id, :equipped)

    # Try to get display_ids from inventory items
    gear_from_inventory =
      equipped_items
      |> Enum.map(fn item ->
        # Look up the item data to get display_id
        case BezgelorData.Store.get(:items, item.item_id) do
          {:ok, item_data} ->
            display_id = Map.get(item_data, "display_id") || Map.get(item_data, :display_id) || 0

            if display_id > 0 do
              %ItemVisual{
                slot: item.slot,
                display_id: display_id,
                colour_set_id: 0,
                dye_data: 0
              }
            else
              nil
            end

          :error ->
            nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    # If we have gear with display_ids, use that; otherwise fall back to class defaults
    if Enum.any?(gear_from_inventory) do
      gear_from_inventory
    else
      # Get default gear visuals based on class
      BezgelorData.Store.get_class_gear_visuals(class_id)
      |> Enum.map(fn %{slot: slot, display_id: display_id} ->
        %ItemVisual{
          slot: slot,
          display_id: display_id,
          colour_set_id: 0,
          dye_data: 0
        }
      end)
    end
  end
end
