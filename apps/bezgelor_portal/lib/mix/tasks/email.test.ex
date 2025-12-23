defmodule Mix.Tasks.Email.Test do
  @moduledoc """
  Send a test email to verify email configuration.

  ## Usage

      # Uses RESEND_API_KEY from environment
      mix email.test recipient@example.com

      # Override API key
      mix email.test recipient@example.com --api-key re_xxxxx

      # Custom sender
      mix email.test recipient@example.com --from noreply@yourdomain.com

  ## Options

    * `--api-key` - Resend API key (defaults to RESEND_API_KEY env var)
    * `--from` - Sender email address (defaults to MAIL_FROM env var or noreply@bezgelor.com)

  """
  use Mix.Task

  @shortdoc "Send a test email to verify configuration"

  @switches [
    api_key: :string,
    from: :string
  ]

  @impl Mix.Task
  def run(args) do
    case OptionParser.parse(args, strict: @switches) do
      {opts, [recipient], []} ->
        send_test_email(recipient, opts)

      {_opts, [], []} ->
        Mix.shell().error("Error: recipient email address required")
        Mix.shell().info("\nUsage: mix email.test recipient@example.com [--api-key KEY] [--from ADDRESS]")

      {_opts, _args, invalid} ->
        Mix.shell().error("Invalid options: #{inspect(invalid)}")
    end
  end

  defp send_test_email(recipient, opts) do
    api_key = opts[:api_key] || System.get_env("RESEND_API_KEY")
    from = opts[:from] || System.get_env("MAIL_FROM", "noreply@bezgelor.com")

    if is_nil(api_key) do
      Mix.shell().error("""
      Error: No API key provided.

      Either:
        1. Set RESEND_API_KEY environment variable
        2. Pass --api-key re_xxxxx

      Get your API key at https://resend.com
      """)
      exit({:shutdown, 1})
    end

    Mix.shell().info("Starting application...")
    Application.ensure_all_started(:bezgelor_portal)

    # Temporarily configure the mailer with the provided API key
    Application.put_env(:bezgelor_portal, BezgelorPortal.Mailer,
      adapter: Swoosh.Adapters.Resend,
      api_key: api_key
    )

    Mix.shell().info("Sending test email...")
    Mix.shell().info("  To: #{recipient}")
    Mix.shell().info("  From: #{from}")

    email =
      Swoosh.Email.new()
      |> Swoosh.Email.to(recipient)
      |> Swoosh.Email.from({"Bezgelor", from})
      |> Swoosh.Email.subject("Bezgelor Test Email")
      |> Swoosh.Email.text_body("""
      This is a test email from Bezgelor.

      If you received this, your email configuration is working correctly!

      Sent at: #{DateTime.utc_now() |> DateTime.to_string()}
      """)
      |> Swoosh.Email.html_body("""
      <div style="font-family: sans-serif; max-width: 600px; margin: 0 auto;">
        <h1 style="color: #6366f1;">Bezgelor Test Email</h1>
        <p>This is a test email from Bezgelor.</p>
        <p style="color: #22c55e; font-weight: bold;">
          If you received this, your email configuration is working correctly!
        </p>
        <hr style="border: none; border-top: 1px solid #e5e7eb; margin: 20px 0;">
        <p style="color: #9ca3af; font-size: 12px;">
          Sent at: #{DateTime.utc_now() |> DateTime.to_string()}
        </p>
      </div>
      """)

    case BezgelorPortal.Mailer.deliver(email) do
      {:ok, _metadata} ->
        Mix.shell().info("\n✓ Email sent successfully!")
        Mix.shell().info("  Check #{recipient} inbox (and spam folder)")

      {:error, reason} ->
        Mix.shell().error("\n✗ Failed to send email")
        Mix.shell().error("  Reason: #{inspect(reason)}")
        exit({:shutdown, 1})
    end
  end
end
