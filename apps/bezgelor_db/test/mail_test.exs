defmodule BezgelorDb.MailTest do
  use ExUnit.Case

  alias BezgelorDb.{Accounts, Characters, Mail, Repo}

  @moduletag :database

  setup do
    case Repo.start_link([]) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})

    # Create test accounts and characters
    email1 = "mail_test#{System.unique_integer([:positive])}@test.com"
    {:ok, account1} = Accounts.create_account(email1, "password123")

    {:ok, sender} =
      Characters.create_character(account1.id, %{
        name: "Sender#{System.unique_integer([:positive])}",
        sex: 0,
        race: 0,
        class: 0,
        faction_id: 166,
        world_id: 1,
        world_zone_id: 1
      })

    email2 = "mail_test#{System.unique_integer([:positive])}@test.com"
    {:ok, account2} = Accounts.create_account(email2, "password123")

    {:ok, recipient} =
      Characters.create_character(account2.id, %{
        name: "Recipient#{System.unique_integer([:positive])}",
        sex: 0,
        race: 0,
        class: 0,
        faction_id: 166,
        world_id: 1,
        world_zone_id: 1
      })

    {:ok, sender: sender, recipient: recipient}
  end

  describe "sending mail" do
    test "send_mail creates mail", %{sender: sender, recipient: recipient} do
      {:ok, mail} =
        Mail.send_mail(%{
          sender_id: sender.id,
          sender_name: sender.name,
          recipient_id: recipient.id,
          subject: "Hello!",
          body: "This is a test message."
        })

      assert mail.subject == "Hello!"
      assert mail.sender_id == sender.id
      assert mail.recipient_id == recipient.id
      assert mail.state == :unread
    end

    test "send_mail with attachments", %{sender: sender, recipient: recipient} do
      attachments = [
        %{item_id: 1001, stack_count: 5},
        %{item_id: 1002, stack_count: 1}
      ]

      {:ok, mail} =
        Mail.send_mail(
          %{
            sender_id: sender.id,
            sender_name: sender.name,
            recipient_id: recipient.id,
            subject: "Items for you"
          },
          attachments
        )

      assert mail.has_attachments

      attached = Mail.get_attachments(mail.id)
      assert length(attached) == 2
      assert Enum.at(attached, 0).item_id == 1001
      assert Enum.at(attached, 1).item_id == 1002
    end

    test "send_mail with gold", %{sender: sender, recipient: recipient} do
      {:ok, mail} =
        Mail.send_mail(%{
          sender_id: sender.id,
          sender_name: sender.name,
          recipient_id: recipient.id,
          subject: "Gold for you",
          gold_attached: 1000
        })

      assert mail.gold_attached == 1000
    end

    test "send_mail with COD", %{sender: sender, recipient: recipient} do
      {:ok, mail} =
        Mail.send_mail(
          %{
            sender_id: sender.id,
            sender_name: sender.name,
            recipient_id: recipient.id,
            subject: "COD Item",
            cod_amount: 500
          },
          [%{item_id: 1001, stack_count: 1}]
        )

      assert mail.cod_amount == 500
    end

    test "send_system_mail creates system mail", %{recipient: recipient} do
      {:ok, mail} =
        Mail.send_system_mail(
          recipient.id,
          "Welcome!",
          "Welcome to the game!",
          gold: 100
        )

      assert mail.is_system_mail
      assert mail.gold_attached == 100
      assert mail.sender_name == "System"
    end
  end

  describe "inbox queries" do
    test "get_inbox returns mail", %{sender: sender, recipient: recipient} do
      {:ok, _} =
        Mail.send_mail(%{
          sender_id: sender.id,
          sender_name: sender.name,
          recipient_id: recipient.id,
          subject: "Test 1"
        })

      {:ok, _} =
        Mail.send_mail(%{
          sender_id: sender.id,
          sender_name: sender.name,
          recipient_id: recipient.id,
          subject: "Test 2"
        })

      inbox = Mail.get_inbox(recipient.id)
      assert length(inbox) == 2
    end

    test "unread_count counts unread mail", %{sender: sender, recipient: recipient} do
      {:ok, mail1} =
        Mail.send_mail(%{
          sender_id: sender.id,
          sender_name: sender.name,
          recipient_id: recipient.id,
          subject: "Test 1"
        })

      {:ok, _} =
        Mail.send_mail(%{
          sender_id: sender.id,
          sender_name: sender.name,
          recipient_id: recipient.id,
          subject: "Test 2"
        })

      assert Mail.unread_count(recipient.id) == 2

      Mail.mark_read(mail1.id)

      assert Mail.unread_count(recipient.id) == 1
    end

    test "has_mail? checks for unread mail", %{sender: sender, recipient: recipient} do
      refute Mail.has_mail?(recipient.id)

      {:ok, _} =
        Mail.send_mail(%{
          sender_id: sender.id,
          sender_name: sender.name,
          recipient_id: recipient.id,
          subject: "Test"
        })

      assert Mail.has_mail?(recipient.id)
    end
  end

  describe "reading mail" do
    test "mark_read changes state", %{sender: sender, recipient: recipient} do
      {:ok, mail} =
        Mail.send_mail(%{
          sender_id: sender.id,
          sender_name: sender.name,
          recipient_id: recipient.id,
          subject: "Test"
        })

      assert mail.state == :unread

      {:ok, updated} = Mail.mark_read(mail.id)

      assert updated.state == :read
    end
  end

  describe "taking gold" do
    test "take_gold returns gold amount", %{sender: sender, recipient: recipient} do
      {:ok, mail} =
        Mail.send_mail(%{
          sender_id: sender.id,
          sender_name: sender.name,
          recipient_id: recipient.id,
          subject: "Gold",
          gold_attached: 1000
        })

      {:ok, gold} = Mail.take_gold(mail.id, recipient.id)

      assert gold == 1000

      # Can't take again
      {:ok, zero} = Mail.take_gold(mail.id, recipient.id)
      assert zero == 0
    end

    test "take_gold fails for non-owner", %{sender: sender, recipient: recipient} do
      {:ok, mail} =
        Mail.send_mail(%{
          sender_id: sender.id,
          sender_name: sender.name,
          recipient_id: recipient.id,
          subject: "Gold",
          gold_attached: 1000
        })

      {:error, :not_owner} = Mail.take_gold(mail.id, sender.id)
    end
  end

  describe "taking attachments" do
    test "take_attachments returns items", %{sender: sender, recipient: recipient} do
      {:ok, mail} =
        Mail.send_mail(
          %{
            sender_id: sender.id,
            sender_name: sender.name,
            recipient_id: recipient.id,
            subject: "Items"
          },
          [%{item_id: 1001, stack_count: 5}]
        )

      {:ok, attachments} = Mail.take_attachments(mail.id, recipient.id)

      assert length(attachments) == 1
      assert hd(attachments).item_id == 1001

      # Attachments are gone
      {:ok, empty} = Mail.take_attachments(mail.id, recipient.id)
      assert empty == []
    end

    test "take_attachments fails with COD", %{sender: sender, recipient: recipient} do
      {:ok, mail} =
        Mail.send_mail(
          %{
            sender_id: sender.id,
            sender_name: sender.name,
            recipient_id: recipient.id,
            subject: "COD",
            cod_amount: 500
          },
          [%{item_id: 1001, stack_count: 1}]
        )

      {:error, {:cod_required, 500}} = Mail.take_attachments(mail.id, recipient.id)
    end

    test "pay_cod_and_take works", %{sender: sender, recipient: recipient} do
      {:ok, mail} =
        Mail.send_mail(
          %{
            sender_id: sender.id,
            sender_name: sender.name,
            recipient_id: recipient.id,
            subject: "COD",
            cod_amount: 500
          },
          [%{item_id: 1001, stack_count: 1}]
        )

      {:ok, attachments, cod_paid} = Mail.pay_cod_and_take(mail.id, recipient.id)

      assert length(attachments) == 1
      assert cod_paid == 500

      # Sender should have received COD payment mail
      sender_inbox = Mail.get_inbox(sender.id)
      assert length(sender_inbox) == 1
      assert hd(sender_inbox).gold_attached == 500
    end
  end

  describe "deleting mail" do
    test "delete_mail removes mail", %{sender: sender, recipient: recipient} do
      {:ok, mail} =
        Mail.send_mail(%{
          sender_id: sender.id,
          sender_name: sender.name,
          recipient_id: recipient.id,
          subject: "Test"
        })

      :ok = Mail.delete_mail(mail.id, recipient.id)

      assert Mail.get_mail(mail.id) == nil
    end

    test "delete_mail fails with attachments", %{sender: sender, recipient: recipient} do
      {:ok, mail} =
        Mail.send_mail(
          %{
            sender_id: sender.id,
            sender_name: sender.name,
            recipient_id: recipient.id,
            subject: "Items"
          },
          [%{item_id: 1001, stack_count: 1}]
        )

      {:error, :has_attachments} = Mail.delete_mail(mail.id, recipient.id)
    end

    test "delete_mail fails with gold", %{sender: sender, recipient: recipient} do
      {:ok, mail} =
        Mail.send_mail(%{
          sender_id: sender.id,
          sender_name: sender.name,
          recipient_id: recipient.id,
          subject: "Gold",
          gold_attached: 100
        })

      {:error, :has_gold} = Mail.delete_mail(mail.id, recipient.id)
    end
  end

  describe "returning mail" do
    test "return_mail sends back to sender", %{sender: sender, recipient: recipient} do
      {:ok, mail} =
        Mail.send_mail(
          %{
            sender_id: sender.id,
            sender_name: sender.name,
            recipient_id: recipient.id,
            subject: "Test",
            gold_attached: 100
          },
          [%{item_id: 1001, stack_count: 1}]
        )

      {:ok, return_mail} = Mail.return_mail(mail.id, recipient.id)

      assert return_mail.recipient_id == sender.id
      assert return_mail.gold_attached == 100
      assert return_mail.subject == "Returned: Test"

      # Original mail is marked returned
      original = Mail.get_mail(mail.id)
      assert original.state == :returned
      assert original.gold_attached == 0
      refute original.has_attachments
    end

    test "cannot return system mail", %{recipient: recipient} do
      {:ok, mail} = Mail.send_system_mail(recipient.id, "Welcome", "Hi!")

      {:error, :cannot_return_system_mail} = Mail.return_mail(mail.id, recipient.id)
    end
  end
end
