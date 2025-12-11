defmodule BezgelorWorld.Handler.LootHandler do
  @moduledoc """
  Handles loot-related packets.

  Processes:
  - Loot rolls (need/greed/pass)
  - Master loot assignments
  - Loot settings changes
  """

  require Logger

  alias BezgelorWorld.Loot.{LootManager, LootRules}
  alias BezgelorProtocol.Packets.World.{
    ServerLootRollResult,
    ServerLootAwarded,
    ServerLootSettings
  }

  @doc """
  Handles player roll response (need/greed/pass).
  """
  def handle_roll(packet, state) do
    character_id = state.session_data[:character_id]
    instance_guid = state.session_data[:instance_guid]

    if character_id && instance_guid do
      roll_type = int_to_roll_type(packet.roll_type)

      case LootManager.submit_roll(instance_guid, packet.loot_id, character_id, roll_type) do
        :ok ->
          Logger.debug("Player #{character_id} rolled #{roll_type} on loot #{packet.loot_id}")
          {:ok, [], state}

        {:error, reason} ->
          Logger.warning("Roll failed: #{inspect(reason)}")
          {:ok, [], state}
      end
    else
      {:ok, [], state}
    end
  end

  @doc """
  Handles master loot assignment.
  """
  def handle_master_assign(packet, state) do
    character_id = state.session_data[:character_id]
    instance_guid = state.session_data[:instance_guid]

    if character_id && instance_guid do
      case LootManager.master_assign(instance_guid, packet.loot_id, character_id, packet.recipient_id) do
        :ok ->
          Logger.info("Master loot: #{character_id} assigned loot #{packet.loot_id} to #{packet.recipient_id}")
          {:ok, [], state}

        {:error, reason} ->
          Logger.warning("Master loot failed: #{inspect(reason)}")
          {:ok, [], state}
      end
    else
      {:ok, [], state}
    end
  end

  @doc """
  Handles loot settings change request.
  """
  def handle_settings_change(packet, state) do
    character_id = state.session_data[:character_id]
    instance_guid = state.session_data[:instance_guid]

    if character_id && instance_guid do
      method = int_to_loot_method(packet.loot_method)

      case LootManager.set_loot_method(instance_guid, character_id, method) do
        :ok ->
          response = %ServerLootSettings{
            loot_method: method
          }

          {:ok, [response], state}

        {:error, reason} ->
          Logger.warning("Settings change failed: #{inspect(reason)}")
          {:ok, [], state}
      end
    else
      {:ok, [], state}
    end
  end

  # Convert wire format to atoms
  defp int_to_roll_type(0), do: :need
  defp int_to_roll_type(1), do: :greed
  defp int_to_roll_type(2), do: :pass
  defp int_to_roll_type(_), do: :pass

  defp int_to_loot_method(0), do: :personal
  defp int_to_loot_method(1), do: :group_loot
  defp int_to_loot_method(2), do: :need_before_greed
  defp int_to_loot_method(3), do: :master_loot
  defp int_to_loot_method(4), do: :round_robin
  defp int_to_loot_method(_), do: :personal
end
