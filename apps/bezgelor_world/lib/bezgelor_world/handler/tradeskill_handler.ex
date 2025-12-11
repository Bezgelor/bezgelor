defmodule BezgelorWorld.Handler.TradeskillHandler do
  @moduledoc """
  Handles tradeskill profession management and talent allocation.

  ## Packets Handled
  - ClientTradeskillLearn - Learn a new profession
  - ClientTradeskillTalentAllocate - Allocate a talent point
  - ClientTradeskillTalentReset - Reset all talents for a profession

  ## Packets Sent
  - ServerTradeskillList - Full profession list
  - ServerTradeskillUpdate - Single profession update
  - ServerTradeskillTalentList - Talent allocation state
  """

  @behaviour BezgelorProtocol.Handler

  require Logger

  alias BezgelorDb.Tradeskills
  alias BezgelorProtocol.PacketReader
  alias BezgelorProtocol.PacketWriter
  alias BezgelorProtocol.Packets.World.{
    ClientTradeskillLearn,
    ClientTradeskillTalentAllocate,
    ClientTradeskillTalentReset,
    ServerTradeskillList,
    ServerTradeskillUpdate,
    ServerTradeskillTalentList
  }
  alias BezgelorWorld.TradeskillConfig

  @impl true
  def handle(payload, state) do
    reader = PacketReader.new(payload)

    with {:error, _} <- try_learn(reader, state),
         {:error, _} <- try_talent_allocate(reader, state),
         {:error, _} <- try_talent_reset(reader, state) do
      {:error, :unknown_tradeskill_packet}
    end
  end

  # Learn profession

  defp try_learn(reader, state) do
    case ClientTradeskillLearn.read(reader) do
      {:ok, packet, _} -> handle_learn(packet, state)
      error -> error
    end
  end

  defp handle_learn(packet, state) do
    character_id = state.session_data[:character_id]

    # Check profession limits
    case check_profession_limit(character_id, packet.profession_type) do
      :ok ->
        case Tradeskills.learn_profession(character_id, packet.profession_id, packet.profession_type) do
          {:ok, tradeskill} ->
            Logger.debug("Character #{character_id} learned profession #{packet.profession_id}")

            response = %ServerTradeskillUpdate{
              profession_id: tradeskill.profession_id,
              profession_type: tradeskill.profession_type,
              skill_level: tradeskill.skill_level,
              skill_xp: tradeskill.skill_xp,
              is_active: tradeskill.is_active,
              levels_gained: 0
            }

            send_packet(response, :server_tradeskill_update, state)

          {:error, reason} ->
            Logger.warning("Failed to learn profession: #{inspect(reason)}")
            {:ok, state}
        end

      {:error, :limit_reached} ->
        Logger.debug("Character #{character_id} at profession limit for #{packet.profession_type}")
        {:ok, state}
    end
  end

  defp check_profession_limit(character_id, profession_type) do
    max_allowed = case profession_type do
      :crafting -> TradeskillConfig.max_crafting_professions()
      :gathering -> TradeskillConfig.max_gathering_professions()
    end

    if max_allowed == 0 do
      :ok
    else
      current = Tradeskills.get_active_professions(character_id, profession_type)
      if length(current) < max_allowed, do: :ok, else: {:error, :limit_reached}
    end
  end

  # Talent allocation

  defp try_talent_allocate(reader, state) do
    case ClientTradeskillTalentAllocate.read(reader) do
      {:ok, packet, _} -> handle_talent_allocate(packet, state)
      error -> error
    end
  end

  defp handle_talent_allocate(packet, state) do
    character_id = state.session_data[:character_id]

    # TODO: Validate talent prerequisites from static data

    case Tradeskills.allocate_talent(character_id, packet.profession_id, packet.talent_id) do
      {:ok, _talent} ->
        Logger.debug("Character #{character_id} allocated talent #{packet.talent_id}")
        send_talent_list(character_id, packet.profession_id, state)

      {:error, reason} ->
        Logger.warning("Failed to allocate talent: #{inspect(reason)}")
        {:ok, state}
    end
  end

  # Talent reset

  defp try_talent_reset(reader, state) do
    case ClientTradeskillTalentReset.read(reader) do
      {:ok, packet, _} -> handle_talent_reset(packet, state)
      error -> error
    end
  end

  defp handle_talent_reset(packet, state) do
    character_id = state.session_data[:character_id]

    case TradeskillConfig.respec_policy() do
      :disabled ->
        Logger.debug("Talent reset disabled by server config")
        {:ok, state}

      :free ->
        do_talent_reset(character_id, packet.profession_id, state)

      :gold_cost ->
        # TODO: Check and deduct gold cost
        cost = TradeskillConfig.respec_gold_cost()
        Logger.debug("Would charge #{cost} copper for talent reset")
        do_talent_reset(character_id, packet.profession_id, state)

      :item_required ->
        # TODO: Check and consume respec item
        Logger.debug("Item-based respec not yet implemented")
        {:ok, state}
    end
  end

  defp do_talent_reset(character_id, profession_id, state) do
    {deleted_count, _} = Tradeskills.reset_talents(character_id, profession_id)
    Logger.debug("Reset #{deleted_count} talents for profession #{profession_id}")
    send_talent_list(character_id, profession_id, state)
  end

  defp send_talent_list(character_id, profession_id, state) do
    talents = Tradeskills.get_talents(character_id, profession_id)
    total_points = Tradeskills.count_talent_points(character_id, profession_id)

    talent_data = Enum.map(talents, fn t ->
      %{talent_id: t.talent_id, points_spent: t.points_spent}
    end)

    response = %ServerTradeskillTalentList{
      profession_id: profession_id,
      total_points: total_points,
      talents: talent_data
    }

    send_packet(response, :server_tradeskill_talent_list, state)
  end

  # Public API for login

  @doc """
  Send tradeskill data to client on login.
  """
  @spec send_tradeskill_data(pid(), integer()) :: :ok
  def send_tradeskill_data(connection_pid, character_id) do
    professions = Tradeskills.get_professions(character_id)

    profession_data = Enum.map(professions, fn p ->
      %{
        profession_id: p.profession_id,
        profession_type: p.profession_type,
        skill_level: p.skill_level,
        skill_xp: p.skill_xp,
        is_active: p.is_active
      }
    end)

    response = %ServerTradeskillList{professions: profession_data}

    writer = PacketWriter.new()
    {:ok, writer} = ServerTradeskillList.write(response, writer)
    packet_data = PacketWriter.to_binary(writer)

    send(connection_pid, {:send_packet, :server_tradeskill_list, packet_data})

    Logger.debug("Sent #{length(professions)} professions to character #{character_id}")
    :ok
  end

  # Helpers

  defp send_packet(packet, opcode, state) do
    writer = PacketWriter.new()
    {:ok, writer} = packet.__struct__.write(packet, writer)
    packet_data = PacketWriter.to_binary(writer)
    {:reply, opcode, packet_data, state}
  end
end
