defmodule BezgelorPortal.EncryptedBinary do
  @moduledoc """
  Cloak-encrypted binary field type.

  Used for storing encrypted TOTP secrets and other sensitive binary data.
  """
  use Cloak.Ecto.Binary, vault: BezgelorPortal.Vault
end
