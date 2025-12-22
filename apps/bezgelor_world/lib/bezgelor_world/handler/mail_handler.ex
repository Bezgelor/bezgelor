defmodule BezgelorWorld.Handler.MailHandler do
  @moduledoc """
  Handler for mail packets.

  ## Packets Handled
  - ClientMailSend
  - ClientMailGetInbox
  - ClientMailRead
  - ClientMailTakeAttachments
  - ClientMailTakeGold
  - ClientMailDelete
  - ClientMailReturn
  """
  @behaviour BezgelorProtocol.Handler

  require Logger

  alias BezgelorProtocol.PacketReader
  alias BezgelorProtocol.PacketWriter

  alias BezgelorProtocol.Packets.World.{
    ClientMailSend,
    ClientMailGetInbox,
    ClientMailRead,
    ClientMailTakeAttachments,
    ClientMailTakeGold,
    ClientMailDelete,
    ClientMailReturn,
    ServerMailList,
    ServerMailResult,
    ServerMailNotification
  }

  alias BezgelorDb.{Mail, Characters}
  alias BezgelorWorld.WorldManager
  alias BezgelorCore.Economy.TelemetryEvents

  @impl true
  def handle(payload, state) do
    reader = PacketReader.new(payload)

    with {:error, _} <- try_send(reader, state),
         {:error, _} <- try_get_inbox(reader, state),
         {:error, _} <- try_read(reader, state),
         {:error, _} <- try_take_attachments(reader, state),
         {:error, _} <- try_take_gold(reader, state),
         {:error, _} <- try_delete(reader, state),
         {:error, _} <- try_return(reader, state) do
      {:error, :unknown_mail_packet}
    end
  end

  # Send mail

  defp try_send(reader, state) do
    case ClientMailSend.read(reader) do
      {:ok, packet, _} -> handle_send(packet, state)
      error -> error
    end
  end

  defp handle_send(packet, state) do
    character_id = state.session_data[:character_id]
    character = Characters.get_character(character_id)

    case Characters.get_character_by_name(packet.recipient_name) do
      nil ->
        send_result(:recipient_not_found, :send, state)

      recipient ->
        # Check recipient inbox size
        inbox = Mail.get_inbox(recipient.id)

        if length(inbox) >= Mail.max_inbox_size() do
          send_result(:inbox_full, :send, state)
        else
          # Build mail attributes
          mail_attrs = %{
            sender_id: character_id,
            sender_name: character.name,
            recipient_id: recipient.id,
            subject: packet.subject,
            body: packet.body,
            gold_attached: packet.gold_attached,
            cod_amount: packet.cod_amount
          }

          # TODO: Convert attachment slots to actual items from inventory
          # For now, we send without attachments
          case Mail.send_mail(mail_attrs, []) do
            {:ok, mail} ->
              Logger.debug("Character #{character_id} sent mail to #{recipient.name}")

              # Emit telemetry event
              TelemetryEvents.emit_mail_sent(
                currency_attached: packet.gold_attached || 0,
                item_count: 0,
                cod_amount: packet.cod_amount || 0,
                sender_id: character_id,
                recipient_id: recipient.id
              )

              # Notify recipient if online
              notify_new_mail(recipient.id)
              send_result(:ok, :send, state, mail_id: mail.id)

            {:error, _} ->
              send_result(:error_unknown, :send, state)
          end
        end
    end
  end

  # Get inbox

  defp try_get_inbox(reader, state) do
    case ClientMailGetInbox.read(reader) do
      {:ok, _packet, _} -> handle_get_inbox(state)
      error -> error
    end
  end

  defp handle_get_inbox(state) do
    character_id = state.session_data[:character_id]
    inbox = Mail.get_inbox(character_id)

    mails =
      Enum.map(inbox, fn mail ->
        attachments = Mail.get_attachments(mail.id)

        %{
          mail_id: mail.id,
          sender_name: mail.sender_name || "Unknown",
          subject: mail.subject || "",
          body: mail.body || "",
          gold_attached: mail.gold_attached || 0,
          cod_amount: mail.cod_amount || 0,
          has_attachments: mail.has_attachments || false,
          is_read: mail.state != :unread,
          sent_time: DateTime.to_unix(mail.inserted_at),
          attachments:
            Enum.map(attachments, fn att ->
              %{
                slot_index: att.slot_index,
                item_id: att.item_id,
                stack_count: att.stack_count
              }
            end)
        }
      end)

    packet = %ServerMailList{mails: mails}
    writer = PacketWriter.new()
    {:ok, writer} = ServerMailList.write(packet, writer)
    packet_data = PacketWriter.to_binary(writer)

    {:reply, :server_mail_list, packet_data, state}
  end

  # Read mail

  defp try_read(reader, state) do
    case ClientMailRead.read(reader) do
      {:ok, packet, _} -> handle_read(packet, state)
      error -> error
    end
  end

  defp handle_read(packet, state) do
    character_id = state.session_data[:character_id]
    mail = Mail.get_mail(packet.mail_id)

    cond do
      mail == nil ->
        send_result(:not_found, :read, state, mail_id: packet.mail_id)

      mail.recipient_id != character_id ->
        send_result(:not_owner, :read, state, mail_id: packet.mail_id)

      true ->
        case Mail.mark_read(packet.mail_id) do
          {:ok, _} ->
            send_result(:ok, :read, state, mail_id: packet.mail_id)

          {:error, _} ->
            send_result(:error_unknown, :read, state, mail_id: packet.mail_id)
        end
    end
  end

  # Take attachments

  defp try_take_attachments(reader, state) do
    case ClientMailTakeAttachments.read(reader) do
      {:ok, packet, _} -> handle_take_attachments(packet, state)
      error -> error
    end
  end

  defp handle_take_attachments(packet, state) do
    character_id = state.session_data[:character_id]

    case Mail.take_attachments(packet.mail_id, character_id) do
      {:ok, _attachments} ->
        # TODO: Add items to player inventory
        Logger.debug("Character #{character_id} took attachments from mail #{packet.mail_id}")
        send_result(:ok, :take_attachments, state, mail_id: packet.mail_id)

      {:error, :not_found} ->
        send_result(:not_found, :take_attachments, state, mail_id: packet.mail_id)

      {:error, :not_owner} ->
        send_result(:not_owner, :take_attachments, state, mail_id: packet.mail_id)

      {:error, {:cod_required, _amount}} ->
        send_result(:cod_required, :take_attachments, state, mail_id: packet.mail_id)

      {:error, _} ->
        send_result(:error_unknown, :take_attachments, state, mail_id: packet.mail_id)
    end
  end

  # Take gold

  defp try_take_gold(reader, state) do
    case ClientMailTakeGold.read(reader) do
      {:ok, packet, _} -> handle_take_gold(packet, state)
      error -> error
    end
  end

  defp handle_take_gold(packet, state) do
    character_id = state.session_data[:character_id]

    case Mail.take_gold(packet.mail_id, character_id) do
      {:ok, _gold} ->
        # TODO: Add gold to player currency
        Logger.debug("Character #{character_id} took gold from mail #{packet.mail_id}")
        send_result(:ok, :take_gold, state, mail_id: packet.mail_id)

      {:error, :not_found} ->
        send_result(:not_found, :take_gold, state, mail_id: packet.mail_id)

      {:error, :not_owner} ->
        send_result(:not_owner, :take_gold, state, mail_id: packet.mail_id)

      {:error, _} ->
        send_result(:error_unknown, :take_gold, state, mail_id: packet.mail_id)
    end
  end

  # Delete mail

  defp try_delete(reader, state) do
    case ClientMailDelete.read(reader) do
      {:ok, packet, _} -> handle_delete(packet, state)
      error -> error
    end
  end

  defp handle_delete(packet, state) do
    character_id = state.session_data[:character_id]

    case Mail.delete_mail(packet.mail_id, character_id) do
      :ok ->
        Logger.debug("Character #{character_id} deleted mail #{packet.mail_id}")
        send_result(:ok, :delete, state, mail_id: packet.mail_id)

      {:error, :not_owner} ->
        send_result(:not_owner, :delete, state, mail_id: packet.mail_id)

      {:error, :has_attachments} ->
        send_result(:has_attachments, :delete, state, mail_id: packet.mail_id)

      {:error, :has_gold} ->
        send_result(:has_gold, :delete, state, mail_id: packet.mail_id)
    end
  end

  # Return mail

  defp try_return(reader, state) do
    case ClientMailReturn.read(reader) do
      {:ok, packet, _} -> handle_return(packet, state)
      error -> error
    end
  end

  defp handle_return(packet, state) do
    character_id = state.session_data[:character_id]

    case Mail.return_mail(packet.mail_id, character_id) do
      {:ok, _return_mail} ->
        Logger.debug("Character #{character_id} returned mail #{packet.mail_id}")
        send_result(:ok, :return, state, mail_id: packet.mail_id)

      {:error, :not_found} ->
        send_result(:not_found, :return, state, mail_id: packet.mail_id)

      {:error, :not_owner} ->
        send_result(:not_owner, :return, state, mail_id: packet.mail_id)

      {:error, :cannot_return_system_mail} ->
        send_result(:cannot_return, :return, state, mail_id: packet.mail_id)

      {:error, :already_returned} ->
        send_result(:cannot_return, :return, state, mail_id: packet.mail_id)

      {:error, :no_sender} ->
        send_result(:cannot_return, :return, state, mail_id: packet.mail_id)

      {:error, _} ->
        send_result(:error_unknown, :return, state, mail_id: packet.mail_id)
    end
  end

  # Public API

  @doc "Send mail notification to a character. Called on world entry or new mail."
  def send_mail_notification(character_id, state) do
    unread = Mail.unread_count(character_id)

    packet = %ServerMailNotification{unread_count: unread}
    writer = PacketWriter.new()
    {:ok, writer} = ServerMailNotification.write(packet, writer)
    packet_data = PacketWriter.to_binary(writer)

    {:reply, :server_mail_notification, packet_data, state}
  end

  # Private helpers

  defp send_result(result, operation, state, opts \\ []) do
    packet = %ServerMailResult{
      result: result,
      operation: operation,
      mail_id: opts[:mail_id]
    }

    writer = PacketWriter.new()
    {:ok, writer} = ServerMailResult.write(packet, writer)
    packet_data = PacketWriter.to_binary(writer)

    {:reply, :server_mail_result, packet_data, state}
  end

  defp notify_new_mail(recipient_id) do
    case WorldManager.get_session_by_character(recipient_id) do
      nil ->
        :ok

      session ->
        unread = Mail.unread_count(recipient_id)
        packet = %ServerMailNotification{unread_count: unread}
        writer = PacketWriter.new()
        {:ok, writer} = ServerMailNotification.write(packet, writer)
        packet_data = PacketWriter.to_binary(writer)
        WorldManager.send_packet(session.pid, :server_mail_notification, packet_data)
    end
  end
end
