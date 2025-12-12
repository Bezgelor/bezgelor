defmodule BezgelorPortal.Vault do
  @moduledoc """
  Cloak vault for encrypting sensitive data in the portal.

  Uses AES-256-GCM encryption for TOTP secrets and other sensitive fields.

  ## Configuration

  In config.exs:

      config :bezgelor_portal, BezgelorPortal.Vault,
        ciphers: [
          default: {Cloak.Ciphers.AES.GCM, tag: "AES.GCM.V1", key: System.get_env("CLOAK_KEY")}
        ]

  Generate a key with: `:crypto.strong_rand_bytes(32) |> Base.encode64()`
  """
  use Cloak.Vault, otp_app: :bezgelor_portal
end
