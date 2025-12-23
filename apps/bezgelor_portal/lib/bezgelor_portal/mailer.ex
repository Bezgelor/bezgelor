defmodule BezgelorPortal.Mailer do
  @moduledoc """
  Email delivery module using Swoosh.

  ## Configuration

  In development, emails are stored locally and can be viewed at `/dev/mailbox`.

  In production, configure Resend via environment variables:
  - `RESEND_API_KEY` - Your Resend API key (get one at https://resend.com)
  - `MAIL_FROM` - Default sender email address (default: noreply@bezgelor.com)

  ## Usage

      import Swoosh.Email
      alias BezgelorPortal.Mailer

      email =
        new()
        |> to("user@example.com")
        |> from({"Bezgelor", "noreply@bezgelor.com"})
        |> subject("Welcome!")
        |> text_body("Hello!")

      Mailer.deliver(email)
  """

  use Swoosh.Mailer, otp_app: :bezgelor_portal
end
