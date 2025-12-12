defmodule BezgelorPortal.Mailer do
  @moduledoc """
  Email delivery module using Swoosh.

  ## Configuration

  In development, emails are stored locally and can be viewed at `/dev/mailbox`.

  In production, configure SMTP settings via environment variables:
  - `SMTP_HOST` - SMTP server hostname
  - `SMTP_PORT` - SMTP server port (default: 587)
  - `SMTP_USERNAME` - SMTP username
  - `SMTP_PASSWORD` - SMTP password
  - `MAIL_FROM` - Default sender email address

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
