defmodule BezgelorWorld.Handler.ReputationHandler do
  @moduledoc """
  Handles reputation-related events.

  Sends reputation list on character login and reputation updates
  when standing changes.
  """

  alias BezgelorDb.Reputation
  alias BezgelorCore.Reputation, as: RepCore
  alias BezgelorProtocol.Packets.World.{ServerReputationList, ServerReputationUpdate}

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
  """
  @spec modify_reputation(pid(), integer(), integer(), integer()) ::
          {:ok, map()} | {:error, term()}
  def modify_reputation(connection_pid, character_id, faction_id, delta) do
    case Reputation.modify_reputation(character_id, faction_id, delta) do
      {:ok, rep} ->
        level = RepCore.standing_to_level(rep.standing)

        packet = %ServerReputationUpdate{
          faction_id: faction_id,
          standing: rep.standing,
          delta: delta,
          level: level
        }

        send(connection_pid, {:send_packet, packet})

        Logger.debug(
          "Reputation updated for character #{character_id}: " <>
            "faction #{faction_id}, delta #{delta}, new standing #{rep.standing} (#{level})"
        )

        {:ok, %{standing: rep.standing, level: level}}

      {:error, reason} ->
        Logger.warning(
          "Failed to modify reputation for character #{character_id}: #{inspect(reason)}"
        )

        {:error, reason}
    end
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
