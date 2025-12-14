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
    ServerMaxCharacterLevelAchieved,
    ServerCharacterList
  }

  alias BezgelorProtocol.{PacketReader, PacketWriter}
  alias BezgelorDb.Characters

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

    if is_nil(account_id) do
      Logger.warning("CharacterListHandler: No account_id in session")
      {:error, :not_authenticated}
    else
      characters = Characters.list_characters(account_id)

      # Calculate max level achieved across all characters
      max_level =
        characters
        |> Enum.map(& &1.level)
        |> Enum.max(fn -> 1 end)

      # Build all the pre-character-list packets
      currency_set = %ServerAccountCurrencySet{currencies: []}
      unlock_list = %ServerGenericUnlockAccountList{unlock_ids: []}
      entitlements = %ServerAccountEntitlements{entitlements: []}
      tier = %ServerAccountTier{tier: 1}
      max_level_packet = %ServerMaxCharacterLevelAchieved{level: max_level}
      character_list = ServerCharacterList.from_characters(characters)

      # Send all packets as encrypted world packets
      responses = [
        {:server_account_currency_set, encode_packet(currency_set)},
        {:server_generic_unlock_account_list, encode_packet(unlock_list)},
        {:server_account_entitlements, encode_packet(entitlements)},
        {:server_account_tier, encode_packet(tier)},
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
end
