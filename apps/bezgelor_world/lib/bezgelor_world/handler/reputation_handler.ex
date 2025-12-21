defmodule BezgelorWorld.Handler.ReputationHandler do
  @moduledoc """
  Handles reputation-related events.

  Sends reputation list on character login and reputation updates
  when standing changes.
  """

  alias BezgelorDb.Reputation
  alias BezgelorCore.Reputation, as: RepCore
  alias BezgelorProtocol.Packets.World.{ServerReputationList, ServerReputationUpdate}
  alias BezgelorWorld.Handler.TitleHandler

  require Logger

  @doc """
  Send full reputation list to client (called on login).
  """
  @spec send_reputation_list(pid(), integer()) :: :ok
  def send_reputation_list(connection_pid, character_id) do
    reputations =
      character_id
      |> Reputation.get_reputations()
      |> Enum.map(fn rep ->
        %{
          faction_id: rep.faction_id,
          standing: rep.standing,
          level: RepCore.standing_to_level(rep.standing)
        }
      end)

    packet = %ServerReputationList{reputations: reputations}
    send(connection_pid, {:send_packet, packet})

    :ok
  end

  @doc """
  Modify reputation and send update to client.

  If account_id is provided, title unlocks will be checked when reputation
  level changes (titles are account-wide).
  """
  @spec modify_reputation(pid(), integer(), integer(), integer(), integer() | nil) ::
          {:ok, map()} | {:error, term()}
  def modify_reputation(connection_pid, character_id, faction_id, delta, account_id \\ nil) do
    # Get old standing to detect level changes
    old_standing = Reputation.get_standing(character_id, faction_id)
    old_level = RepCore.standing_to_level(old_standing)

    case Reputation.modify_reputation(character_id, faction_id, delta) do
      {:ok, rep} ->
        new_level = RepCore.standing_to_level(rep.standing)

        packet = %ServerReputationUpdate{
          faction_id: faction_id,
          standing: rep.standing,
          delta: delta,
          level: new_level
        }

        send(connection_pid, {:send_packet, packet})

        Logger.debug(
          "Reputation updated for character #{character_id}: " <>
            "faction #{faction_id}, delta #{delta}, new standing #{rep.standing} (#{new_level})"
        )

        # Check for title unlocks if level increased and account_id provided
        if account_id && level_increased?(old_level, new_level) do
          TitleHandler.check_reputation_titles(connection_pid, account_id, faction_id, new_level)
        end

        {:ok, %{standing: rep.standing, level: new_level, level_changed: old_level != new_level}}

      {:error, reason} ->
        Logger.warning(
          "Failed to modify reputation for character #{character_id}: #{inspect(reason)}"
        )

        {:error, reason}
    end
  end

  # Check if reputation level increased (for title unlocks)
  defp level_increased?(old_level, new_level) do
    level_order = [
      :hated,
      :hostile,
      :unfriendly,
      :neutral,
      :friendly,
      :honored,
      :revered,
      :exalted
    ]

    old_idx = Enum.find_index(level_order, &(&1 == old_level)) || 0
    new_idx = Enum.find_index(level_order, &(&1 == new_level)) || 0
    new_idx > old_idx
  end

  @doc """
  Check if character can purchase from faction vendor.
  """
  @spec can_purchase?(integer(), integer()) :: boolean()
  def can_purchase?(character_id, faction_id) do
    Reputation.can_purchase?(character_id, faction_id)
  end

  @doc """
  Get vendor discount for character with faction.
  """
  @spec get_vendor_discount(integer(), integer()) :: float()
  def get_vendor_discount(character_id, faction_id) do
    Reputation.get_vendor_discount(character_id, faction_id)
  end

  @doc """
  Check if character meets reputation requirement for quest/item.
  """
  @spec meets_requirement?(integer(), integer(), atom()) :: boolean()
  def meets_requirement?(character_id, faction_id, required_level) do
    Reputation.meets_requirement?(character_id, faction_id, required_level)
  end
end
