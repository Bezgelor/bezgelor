defmodule BezgelorProtocol.Handler.RealmListHandler do
  @moduledoc """
  Handler for ClientRealmList packets.

  Called when the player clicks "Change Realm" on the character select screen.
  Responds with a ServerRealmList containing all available realms from the database.

  ## Response

  Sends ServerRealmList with:
  - All realms from database with current status
  - Per-realm character counts for the account
  - Last played character info per realm
  """

  @behaviour BezgelorProtocol.Handler

  alias BezgelorProtocol.Packets.World.ServerRealmList
  alias BezgelorProtocol.PacketWriter
  alias BezgelorDb.Characters
  alias BezgelorDb.Realms

  require Logger

  @impl true
  def handle(_payload, state) do
    # ClientRealmList has no payload (empty packet)
    send_realm_list(state)
  end

  defp send_realm_list(state) do
    account_id = get_in(state.session_data, [:account_id])
    current_realm_id = Application.get_env(:bezgelor_realm, :realm_id, 1)

    # Get all realms from database
    realms = Realms.list_realms()

    # Build realm list from database with per-realm character counts
    realm_list =
      ServerRealmList.from_realms(realms, account_id, current_realm_id,
        get_character_count: &get_character_count/2,
        get_last_played: &get_last_played/2
      )

    Logger.debug(
      "Sending realm list: #{length(realm_list.realms)} realm(s) for account #{account_id}"
    )

    # Encode and send as encrypted world packet
    writer = PacketWriter.new()
    {:ok, writer} = ServerRealmList.write(realm_list, writer)
    data = PacketWriter.to_binary(writer)

    {:reply_world_encrypted, :server_realm_list, data, state}
  end

  # Get character count for an account on a specific realm
  defp get_character_count(nil, _realm_id), do: 0

  defp get_character_count(account_id, realm_id) do
    Characters.count_characters(account_id, realm_id)
  end

  # Get last played character info for an account on a specific realm
  defp get_last_played(nil, _realm_id), do: {"", 0}

  defp get_last_played(account_id, realm_id) do
    characters = Characters.list_characters(account_id, realm_id)

    characters
    |> Enum.filter(&(&1.last_online != nil))
    |> Enum.max_by(fn c -> c.last_online end, DateTime, fn -> nil end)
    |> case do
      nil ->
        # No characters with last_online, use first character if any
        case characters do
          [first | _] -> {first.name, 0}
          [] -> {"", 0}
        end

      %{} = char ->
        time =
          if char.last_online do
            DateTime.to_unix(char.last_online, :millisecond)
          else
            0
          end

        {char.name, time}
    end
  end
end
