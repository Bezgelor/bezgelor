defmodule BezgelorWorld.Handler.GuildHandler do
  @moduledoc """
  Handler for guild packets.

  ## Packets Handled
  - ClientGuildCreate
  - ClientGuildInvite
  - ClientGuildAcceptInvite
  - ClientGuildDeclineInvite
  - ClientGuildLeave
  - ClientGuildKick
  - ClientGuildPromote
  - ClientGuildDemote
  - ClientGuildSetMotd
  - ClientGuildDisband
  """
  @behaviour BezgelorProtocol.Handler

  require Logger

  alias BezgelorProtocol.PacketReader
  alias BezgelorProtocol.PacketWriter
  alias BezgelorProtocol.Packets.World.{
    ClientGuildCreate,
    ClientGuildInvite,
    ClientGuildAcceptInvite,
    ClientGuildDeclineInvite,
    ClientGuildLeave,
    ClientGuildKick,
    ClientGuildPromote,
    ClientGuildDemote,
    ClientGuildSetMotd,
    ClientGuildDisband,
    ServerGuildData,
    ServerGuildMemberUpdate,
    ServerGuildResult
  }
  alias BezgelorDb.{Guilds, Characters}
  alias BezgelorWorld.WorldManager

  @impl true
  def handle(payload, state) do
    reader = PacketReader.new(payload)

    with {:error, _} <- try_create(reader, state),
         {:error, _} <- try_invite(reader, state),
         {:error, _} <- try_accept_invite(reader, state),
         {:error, _} <- try_decline_invite(reader, state),
         {:error, _} <- try_leave(reader, state),
         {:error, _} <- try_kick(reader, state),
         {:error, _} <- try_promote(reader, state),
         {:error, _} <- try_demote(reader, state),
         {:error, _} <- try_set_motd(reader, state),
         {:error, _} <- try_disband(reader, state) do
      {:error, :unknown_guild_packet}
    end
  end

  # Create guild

  defp try_create(reader, state) do
    case ClientGuildCreate.read(reader) do
      {:ok, packet, _} -> handle_create(packet, state)
      error -> error
    end
  end

  defp handle_create(packet, state) do
    character_id = state.session_data[:character_id]

    case Guilds.create_guild(character_id, packet.name, packet.tag) do
      {:ok, guild} ->
        Logger.info("Character #{character_id} created guild: #{guild.name}")
        send_result(:ok, :create, state, guild_id: guild.id, guild_name: guild.name)

      {:error, :already_in_guild} ->
        send_result(:already_in_guild, :create, state)

      {:error, _changeset} ->
        send_result(:invalid_name, :create, state)
    end
  end

  # Invite

  defp try_invite(reader, state) do
    case ClientGuildInvite.read(reader) do
      {:ok, packet, _} -> handle_invite(packet, state)
      error -> error
    end
  end

  defp handle_invite(packet, state) do
    character_id = state.session_data[:character_id]

    case Guilds.get_membership(character_id) do
      nil ->
        send_result(:not_in_guild, :invite, state)

      membership ->
        case Characters.get_character_by_name(packet.target_name) do
          nil ->
            send_result(:target_not_found, :invite, state, target_name: packet.target_name)

          target ->
            case Guilds.add_member(membership.guild_id, target.id, character_id) do
              {:ok, _member} ->
                Logger.debug("Character #{character_id} invited #{target.name} to guild")
                # Notify the target of the invite
                broadcast_member_update(membership.guild_id, target.id, target.name, :join, 4)
                send_result(:ok, :invite, state, target_name: packet.target_name)

              {:error, :no_permission} ->
                send_result(:insufficient_rank, :invite, state, target_name: packet.target_name)

              {:error, :already_in_guild} ->
                send_result(:target_in_guild, :invite, state, target_name: packet.target_name)

              {:error, _} ->
                send_result(:error_unknown, :invite, state, target_name: packet.target_name)
            end
        end
    end
  end

  # Accept invite (simplified - assumes direct join for now)

  defp try_accept_invite(reader, state) do
    case ClientGuildAcceptInvite.read(reader) do
      {:ok, packet, _} -> handle_accept_invite(packet, state)
      error -> error
    end
  end

  defp handle_accept_invite(_packet, state) do
    # In a full implementation, this would handle pending invites
    # For now, members are added directly on invite
    send_result(:ok, :accept_invite, state)
  end

  # Decline invite

  defp try_decline_invite(reader, state) do
    case ClientGuildDeclineInvite.read(reader) do
      {:ok, packet, _} -> handle_decline_invite(packet, state)
      error -> error
    end
  end

  defp handle_decline_invite(_packet, state) do
    send_result(:ok, :decline_invite, state)
  end

  # Leave guild

  defp try_leave(reader, state) do
    case ClientGuildLeave.read(reader) do
      {:ok, _packet, _} -> handle_leave(state)
      error -> error
    end
  end

  defp handle_leave(state) do
    character_id = state.session_data[:character_id]

    case Guilds.get_membership(character_id) do
      nil ->
        send_result(:not_in_guild, :leave, state)

      membership ->
        guild_id = membership.guild_id

        case Guilds.leave_guild(character_id) do
          :ok ->
            Logger.debug("Character #{character_id} left guild #{guild_id}")
            broadcast_member_update(guild_id, character_id, "", :leave, 0)
            send_result(:ok, :leave, state)

          {:error, :leader_cannot_leave} ->
            send_result(:insufficient_rank, :leave, state)
        end
    end
  end

  # Kick member

  defp try_kick(reader, state) do
    case ClientGuildKick.read(reader) do
      {:ok, packet, _} -> handle_kick(packet, state)
      error -> error
    end
  end

  defp handle_kick(packet, state) do
    character_id = state.session_data[:character_id]

    case Guilds.get_membership(character_id) do
      nil ->
        send_result(:not_in_guild, :kick, state)

      membership ->
        case Guilds.remove_member(membership.guild_id, packet.target_id, character_id) do
          :ok ->
            Logger.debug("Character #{character_id} kicked #{packet.target_id} from guild")
            broadcast_member_update(membership.guild_id, packet.target_id, "", :leave, 0)
            send_result(:ok, :kick, state)

          {:error, :no_permission} ->
            send_result(:insufficient_rank, :kick, state)

          {:error, :cannot_kick_leader} ->
            send_result(:insufficient_rank, :kick, state)

          {:error, :cannot_kick_higher_rank} ->
            send_result(:insufficient_rank, :kick, state)

          {:error, _} ->
            send_result(:error_unknown, :kick, state)
        end
    end
  end

  # Promote member

  defp try_promote(reader, state) do
    case ClientGuildPromote.read(reader) do
      {:ok, packet, _} -> handle_promote(packet, state)
      error -> error
    end
  end

  defp handle_promote(packet, state) do
    character_id = state.session_data[:character_id]

    case Guilds.get_membership(character_id) do
      nil ->
        send_result(:not_in_guild, :promote, state)

      membership ->
        case Guilds.promote_member(membership.guild_id, packet.target_id, character_id) do
          {:ok, updated_member} ->
            Logger.debug("Character #{character_id} promoted #{packet.target_id}")
            broadcast_rank_change(membership.guild_id, packet.target_id, updated_member.rank_index)
            send_result(:ok, :promote, state)

          {:error, :no_permission} ->
            send_result(:insufficient_rank, :promote, state)

          {:error, _} ->
            send_result(:error_unknown, :promote, state)
        end
    end
  end

  # Demote member

  defp try_demote(reader, state) do
    case ClientGuildDemote.read(reader) do
      {:ok, packet, _} -> handle_demote(packet, state)
      error -> error
    end
  end

  defp handle_demote(packet, state) do
    character_id = state.session_data[:character_id]

    case Guilds.get_membership(character_id) do
      nil ->
        send_result(:not_in_guild, :demote, state)

      membership ->
        case Guilds.demote_member(membership.guild_id, packet.target_id, character_id) do
          {:ok, updated_member} ->
            Logger.debug("Character #{character_id} demoted #{packet.target_id}")
            broadcast_rank_change(membership.guild_id, packet.target_id, updated_member.rank_index)
            send_result(:ok, :demote, state)

          {:error, :no_permission} ->
            send_result(:insufficient_rank, :demote, state)

          {:error, _} ->
            send_result(:error_unknown, :demote, state)
        end
    end
  end

  # Set MOTD

  defp try_set_motd(reader, state) do
    case ClientGuildSetMotd.read(reader) do
      {:ok, packet, _} -> handle_set_motd(packet, state)
      error -> error
    end
  end

  defp handle_set_motd(packet, state) do
    character_id = state.session_data[:character_id]

    case Guilds.get_membership(character_id) do
      nil ->
        send_result(:not_in_guild, :set_motd, state)

      membership ->
        case Guilds.update_motd(membership.guild_id, packet.motd, character_id) do
          {:ok, _guild} ->
            Logger.debug("Character #{character_id} updated guild MOTD")
            send_result(:ok, :set_motd, state)

          {:error, :no_permission} ->
            send_result(:insufficient_rank, :set_motd, state)

          {:error, _} ->
            send_result(:error_unknown, :set_motd, state)
        end
    end
  end

  # Disband guild

  defp try_disband(reader, state) do
    case ClientGuildDisband.read(reader) do
      {:ok, _packet, _} -> handle_disband(state)
      error -> error
    end
  end

  defp handle_disband(state) do
    character_id = state.session_data[:character_id]

    case Guilds.get_membership(character_id) do
      nil ->
        send_result(:not_in_guild, :disband, state)

      membership ->
        case Guilds.disband_guild(membership.guild_id, character_id) do
          :ok ->
            Logger.info("Character #{character_id} disbanded guild #{membership.guild_id}")
            send_result(:ok, :disband, state)

          {:error, :no_permission} ->
            send_result(:insufficient_rank, :disband, state)

          {:error, _} ->
            send_result(:error_unknown, :disband, state)
        end
    end
  end

  # Public API for sending guild data on login

  @doc "Send guild data to a character. Called on world entry."
  def send_guild_data(character_id, state) do
    packet =
      case Guilds.get_membership(character_id) do
        nil ->
          %ServerGuildData{has_guild: false}

        membership ->
          guild = Guilds.get_guild(membership.guild_id)
          ranks = Guilds.get_ranks(membership.guild_id)
          members = Guilds.get_members(membership.guild_id)

          rank_data =
            Enum.map(ranks, fn rank ->
              %{
                rank_index: rank.rank_index,
                name: rank.name,
                permissions: rank.permissions
              }
            end)

          member_data =
            Enum.map(members, fn member ->
              char = Characters.get_character(member.character_id)
              online_session = WorldManager.get_session_by_character(member.character_id)

              %{
                character_id: member.character_id,
                name: char.name,
                rank_index: member.rank_index,
                online: online_session != nil
              }
            end)

          %ServerGuildData{
            has_guild: true,
            guild_id: guild.id,
            name: guild.name,
            tag: guild.tag,
            motd: guild.motd || "",
            influence: guild.influence,
            ranks: rank_data,
            members: member_data
          }
      end

    writer = PacketWriter.new()
    {:ok, writer} = ServerGuildData.write(packet, writer)
    packet_data = PacketWriter.to_binary(writer)

    {:reply, :server_guild_data, packet_data, state}
  end

  # Private helpers

  defp send_result(result, operation, state, opts \\ []) do
    packet = %ServerGuildResult{
      result: result,
      operation: operation,
      guild_id: opts[:guild_id],
      guild_name: opts[:guild_name],
      target_name: opts[:target_name]
    }

    writer = PacketWriter.new()
    {:ok, writer} = ServerGuildResult.write(packet, writer)
    packet_data = PacketWriter.to_binary(writer)

    {:reply, :server_guild_result, packet_data, state}
  end

  defp broadcast_member_update(guild_id, character_id, name, update_type, rank_index) do
    packet = %ServerGuildMemberUpdate{
      update_type: update_type,
      character_id: character_id,
      name: name,
      rank_index: rank_index
    }

    writer = PacketWriter.new()
    {:ok, writer} = ServerGuildMemberUpdate.write(packet, writer)
    packet_data = PacketWriter.to_binary(writer)

    # Broadcast to all online guild members
    members = Guilds.get_members(guild_id)

    for member <- members do
      case WorldManager.get_session_by_character(member.character_id) do
        nil -> :ok
        session -> WorldManager.send_packet(session.pid, :server_guild_member_update, packet_data)
      end
    end
  end

  defp broadcast_rank_change(guild_id, character_id, new_rank) do
    packet = %ServerGuildMemberUpdate{
      update_type: :rank_change,
      character_id: character_id,
      rank_index: new_rank
    }

    writer = PacketWriter.new()
    {:ok, writer} = ServerGuildMemberUpdate.write(packet, writer)
    packet_data = PacketWriter.to_binary(writer)

    members = Guilds.get_members(guild_id)

    for member <- members do
      case WorldManager.get_session_by_character(member.character_id) do
        nil -> :ok
        session -> WorldManager.send_packet(session.pid, :server_guild_member_update, packet_data)
      end
    end
  end
end
