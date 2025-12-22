defmodule BezgelorDb.Mail do
  @moduledoc """
  Mail system context.

  ## Features

  - Send text messages between characters
  - Attach items and currency
  - Cash on Delivery (COD) - recipient pays to receive
  - Return mail to sender
  - System mail from NPCs/events

  ## Mail Lifecycle

  1. Sender creates mail with send_mail/2
  2. Recipient views inbox with get_inbox/1
  3. Recipient opens mail (mark_read/1)
  4. Recipient takes attachments/gold (take_attachments/1, take_gold/1)
  5. Recipient deletes mail or it expires

  ## COD (Cash on Delivery)

  If cod_amount > 0, recipient must pay that amount to take attachments.
  The payment is sent to the original sender via return mail.
  """

  import Ecto.Query
  alias BezgelorDb.Repo
  alias BezgelorDb.Schema.{Mail, MailAttachment}
  alias BezgelorCore.Economy.TelemetryEvents

  @max_inbox_size 50

  # Queries

  @doc "Get mail by ID."
  @spec get_mail(integer()) :: Mail.t() | nil
  def get_mail(mail_id) do
    Repo.get(Mail, mail_id)
  end

  @doc "Get character's inbox (non-expired mail)."
  @spec get_inbox(integer()) :: [Mail.t()]
  def get_inbox(character_id) do
    now = DateTime.utc_now()

    Mail
    |> where([m], m.recipient_id == ^character_id)
    |> where([m], m.expires_at > ^now)
    |> order_by([m], desc: m.inserted_at)
    |> limit(@max_inbox_size)
    |> Repo.all()
  end

  @doc "Get unread mail count."
  @spec unread_count(integer()) :: integer()
  def unread_count(character_id) do
    now = DateTime.utc_now()

    Mail
    |> where([m], m.recipient_id == ^character_id and m.state == :unread)
    |> where([m], m.expires_at > ^now)
    |> Repo.aggregate(:count)
  end

  @doc "Get attachments for a mail."
  @spec get_attachments(integer()) :: [MailAttachment.t()]
  def get_attachments(mail_id) do
    MailAttachment
    |> where([a], a.mail_id == ^mail_id)
    |> order_by([a], a.slot_index)
    |> Repo.all()
  end

  @doc "Check if character has mail."
  @spec has_mail?(integer()) :: boolean()
  def has_mail?(character_id) do
    unread_count(character_id) > 0
  end

  # Sending Mail

  @doc "Send a mail message."
  @spec send_mail(map(), list()) :: {:ok, Mail.t()} | {:error, term()}
  def send_mail(mail_attrs, attachments \\ []) do
    Repo.transaction(fn ->
      # Create mail
      has_attachments = length(attachments) > 0

      {:ok, mail} =
        %Mail{}
        |> Mail.changeset(Map.put(mail_attrs, :has_attachments, has_attachments))
        |> Repo.insert()

      # Add attachments
      for {attachment_data, index} <- Enum.with_index(attachments) do
        %MailAttachment{}
        |> MailAttachment.changeset(
          Map.merge(attachment_data, %{mail_id: mail.id, slot_index: index})
        )
        |> Repo.insert!()
      end

      mail
    end)
  end

  @doc "Send system mail (no sender)."
  @spec send_system_mail(integer(), String.t(), String.t(), keyword()) ::
          {:ok, Mail.t()} | {:error, term()}
  def send_system_mail(recipient_id, subject, body, opts \\ []) do
    gold = Keyword.get(opts, :gold, 0)
    attachments = Keyword.get(opts, :attachments, [])

    result =
      send_mail(
        %{
          recipient_id: recipient_id,
          sender_name: Keyword.get(opts, :sender_name, "System"),
          subject: subject,
          body: body,
          gold_attached: gold,
          is_system_mail: true
        },
        attachments
      )

    case result do
      {:ok, _mail} ->
        # Emit telemetry for system mail
        TelemetryEvents.emit_mail_sent(
          currency_attached: gold,
          item_count: length(attachments),
          cod_amount: 0,
          sender_id: 0,
          recipient_id: recipient_id
        )

        result

      error ->
        error
    end
  end

  # Reading and Taking

  @doc "Mark mail as read."
  @spec mark_read(integer()) :: {:ok, Mail.t()} | {:error, term()}
  def mark_read(mail_id) do
    case get_mail(mail_id) do
      nil ->
        {:error, :not_found}

      %{state: :unread} = mail ->
        mail
        |> Mail.read_changeset()
        |> Repo.update()

      mail ->
        {:ok, mail}
    end
  end

  @doc "Take gold from mail."
  @spec take_gold(integer(), integer()) :: {:ok, integer()} | {:error, term()}
  def take_gold(mail_id, requester_id) do
    case get_mail(mail_id) do
      nil ->
        {:error, :not_found}

      %{recipient_id: recipient_id} when recipient_id != requester_id ->
        {:error, :not_owner}

      %{gold_attached: 0} ->
        {:ok, 0}

      mail ->
        gold = mail.gold_attached

        {:ok, _} =
          mail
          |> Mail.take_gold_changeset()
          |> Repo.update()

        {:ok, gold}
    end
  end

  @doc "Take attachments from mail (handles COD)."
  @spec take_attachments(integer(), integer()) ::
          {:ok, [MailAttachment.t()]} | {:error, term()}
  def take_attachments(mail_id, requester_id) do
    case get_mail(mail_id) do
      nil ->
        {:error, :not_found}

      %{recipient_id: recipient_id} when recipient_id != requester_id ->
        {:error, :not_owner}

      %{has_attachments: false} ->
        {:ok, []}

      %{cod_amount: cod} when cod > 0 ->
        {:error, {:cod_required, cod}}

      mail ->
        attachments = get_attachments(mail.id)

        # Clear attachments
        Repo.delete_all(from(a in MailAttachment, where: a.mail_id == ^mail.id))

        {:ok, _} =
          mail
          |> Mail.take_attachments_changeset()
          |> Repo.update()

        {:ok, attachments}
    end
  end

  @doc "Pay COD and take attachments."
  @spec pay_cod_and_take(integer(), integer()) ::
          {:ok, [MailAttachment.t()], integer()} | {:error, term()}
  def pay_cod_and_take(mail_id, requester_id) do
    case get_mail(mail_id) do
      nil ->
        {:error, :not_found}

      %{recipient_id: recipient_id} when recipient_id != requester_id ->
        {:error, :not_owner}

      %{has_attachments: false} ->
        {:ok, [], 0}

      %{cod_amount: 0} = mail ->
        {:ok, attachments} = take_attachments(mail.id, requester_id)
        {:ok, attachments, 0}

      mail ->
        cod = mail.cod_amount
        attachments = get_attachments(mail.id)

        Repo.transaction(fn ->
          # Clear attachments and COD
          Repo.delete_all(from(a in MailAttachment, where: a.mail_id == ^mail.id))

          mail
          |> Ecto.Changeset.change(has_attachments: false, cod_amount: 0)
          |> Repo.update!()

          # Send COD payment to original sender if it was a player mail
          if mail.sender_id do
            {:ok, _cod_mail} =
              send_mail(%{
                recipient_id: mail.sender_id,
                sender_name: "COD Payment",
                subject: "COD Payment Received",
                body: "Your COD payment of #{cod} gold has been received.",
                gold_attached: cod,
                is_system_mail: true
              })

            # Emit telemetry for COD payment mail
            TelemetryEvents.emit_mail_sent(
              currency_attached: cod,
              item_count: 0,
              cod_amount: 0,
              sender_id: mail.recipient_id,
              recipient_id: mail.sender_id
            )
          end

          {attachments, cod}
        end)
        |> case do
          {:ok, {attachments, cod}} -> {:ok, attachments, cod}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  # Deleting and Returning

  @doc "Delete a mail."
  @spec delete_mail(integer(), integer()) :: :ok | {:error, term()}
  def delete_mail(mail_id, requester_id) do
    case get_mail(mail_id) do
      nil ->
        :ok

      %{recipient_id: recipient_id} when recipient_id != requester_id ->
        {:error, :not_owner}

      %{has_attachments: true} ->
        {:error, :has_attachments}

      %{gold_attached: gold} when gold > 0 ->
        {:error, :has_gold}

      mail ->
        Repo.delete(mail)
        :ok
    end
  end

  @doc "Return mail to sender."
  @spec return_mail(integer(), integer()) :: {:ok, Mail.t()} | {:error, term()}
  def return_mail(mail_id, requester_id) do
    case get_mail(mail_id) do
      nil ->
        {:error, :not_found}

      %{recipient_id: recipient_id} when recipient_id != requester_id ->
        {:error, :not_owner}

      %{is_system_mail: true} ->
        {:error, :cannot_return_system_mail}

      %{state: :returned} ->
        {:error, :already_returned}

      %{sender_id: nil} ->
        {:error, :no_sender}

      mail ->
        Repo.transaction(fn ->
          # Create return mail
          attachments = get_attachments(mail.id)

          {:ok, return_mail} =
            send_mail(
              %{
                sender_id: mail.recipient_id,
                sender_name: "Returned Mail",
                recipient_id: mail.sender_id,
                subject: "Returned: #{mail.subject}",
                body: mail.body,
                gold_attached: mail.gold_attached,
                # No COD on returns
                cod_amount: 0
              },
              Enum.map(attachments, fn a ->
                %{item_id: a.item_id, stack_count: a.stack_count, item_data: a.item_data}
              end)
            )

          # Emit telemetry for returned mail
          TelemetryEvents.emit_mail_sent(
            currency_attached: mail.gold_attached || 0,
            item_count: length(attachments),
            cod_amount: 0,
            sender_id: mail.recipient_id,
            recipient_id: mail.sender_id
          )

          # Mark original as returned and clear contents
          Repo.delete_all(from(a in MailAttachment, where: a.mail_id == ^mail.id))

          mail
          |> Ecto.Changeset.change(
            state: :returned,
            gold_attached: 0,
            has_attachments: false,
            cod_amount: 0
          )
          |> Repo.update!()

          return_mail
        end)
    end
  end

  # Cleanup

  @doc "Delete expired mail (for scheduled cleanup)."
  @spec cleanup_expired() :: {integer(), nil}
  def cleanup_expired do
    now = DateTime.utc_now()

    # First delete attachments of expired mail
    expired_mail_ids =
      Mail
      |> where([m], m.expires_at <= ^now)
      |> select([m], m.id)

    Repo.delete_all(from(a in MailAttachment, where: a.mail_id in subquery(expired_mail_ids)))

    # Then delete the mail
    Repo.delete_all(from(m in Mail, where: m.expires_at <= ^now))
  end

  def max_inbox_size, do: @max_inbox_size
end
