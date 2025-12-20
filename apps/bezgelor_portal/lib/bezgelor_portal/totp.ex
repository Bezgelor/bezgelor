defmodule BezgelorPortal.TOTP do
  @moduledoc """
  Two-Factor Authentication (TOTP) functionality.

  Handles generating secrets, validating codes, creating QR codes,
  and managing backup codes.

  ## Usage

      # Generate a new TOTP setup
      {:ok, setup} = TOTP.generate_setup("user@example.com")

      # Validate a code
      :ok = TOTP.validate_code(secret, "123456")

      # Generate backup codes
      {codes, hashed_codes} = TOTP.generate_backup_codes()
  """

  alias BezgelorDb.Schema.Account
  alias BezgelorDb.Repo
  alias BezgelorPortal.Vault

  @issuer "Bezgelor"
  @backup_code_count 8

  @doc """
  Generate a new TOTP setup for an account.

  Returns a map containing:
  - `:secret` - The raw TOTP secret
  - `:secret_base32` - The secret in base32 format (for manual entry)
  - `:otpauth_uri` - The otpauth:// URI for QR code generation
  - `:qr_code_svg` - SVG string for the QR code
  """
  @spec generate_setup(String.t()) :: {:ok, map()}
  def generate_setup(email) do
    secret = NimbleTOTP.secret()
    secret_base32 = Base.encode32(secret, padding: false)

    otpauth_uri = NimbleTOTP.otpauth_uri("#{@issuer}:#{email}", secret, issuer: @issuer)

    qr_code_svg = generate_qr_svg(otpauth_uri)

    {:ok,
     %{
       secret: secret,
       secret_base32: secret_base32,
       otpauth_uri: otpauth_uri,
       qr_code_svg: qr_code_svg
     }}
  end

  @doc """
  Validate a TOTP code against a secret.

  Allows for time drift of one period (30 seconds) in either direction.
  """
  @spec validate_code(binary(), String.t()) :: :ok | {:error, :invalid_code}
  def validate_code(secret, code) when is_binary(secret) and is_binary(code) do
    if NimbleTOTP.valid?(secret, code) do
      :ok
    else
      {:error, :invalid_code}
    end
  end

  @doc """
  Generate backup codes.

  Returns a tuple of {plaintext_codes, hashed_codes} where:
  - `plaintext_codes` - List of 8 human-readable codes (show to user once)
  - `hashed_codes` - List of hashed codes (store in database)
  """
  @spec generate_backup_codes() :: {[String.t()], [String.t()]}
  def generate_backup_codes do
    codes =
      for _ <- 1..@backup_code_count do
        generate_backup_code()
      end

    hashed_codes =
      Enum.map(codes, fn code ->
        :crypto.hash(:sha256, code) |> Base.encode64()
      end)

    {codes, hashed_codes}
  end

  @doc """
  Verify a backup code against stored hashed codes.

  Returns `{:ok, remaining_hashes}` if valid, or `{:error, :invalid_code}` if not.
  The remaining_hashes should be stored back to remove the used code.
  """
  @spec verify_backup_code(String.t(), [String.t()]) ::
          {:ok, [String.t()]} | {:error, :invalid_code}
  def verify_backup_code(code, hashed_codes) when is_binary(code) and is_list(hashed_codes) do
    code_hash = :crypto.hash(:sha256, normalize_backup_code(code)) |> Base.encode64()

    if code_hash in hashed_codes do
      remaining = List.delete(hashed_codes, code_hash)
      {:ok, remaining}
    else
      {:error, :invalid_code}
    end
  end

  @doc """
  Enable TOTP for an account.

  Encrypts and stores the secret, stores hashed backup codes, and sets
  `totp_enabled_at` timestamp.
  """
  @spec enable_totp(Account.t(), binary(), [String.t()]) ::
          {:ok, Account.t()} | {:error, Ecto.Changeset.t()}
  def enable_totp(account, secret, hashed_backup_codes) do
    encrypted_secret = Vault.encrypt!(secret)

    account
    |> Ecto.Changeset.change(%{
      totp_secret_encrypted: encrypted_secret,
      totp_enabled_at: DateTime.utc_now() |> DateTime.truncate(:second),
      backup_codes_hashed: hashed_backup_codes
    })
    |> Repo.update()
  end

  @doc """
  Disable TOTP for an account.

  Clears the secret, backup codes, and enabled timestamp.
  """
  @spec disable_totp(Account.t()) :: {:ok, Account.t()} | {:error, Ecto.Changeset.t()}
  def disable_totp(account) do
    account
    |> Ecto.Changeset.change(%{
      totp_secret_encrypted: nil,
      totp_enabled_at: nil,
      backup_codes_hashed: nil
    })
    |> Repo.update()
  end

  @doc """
  Check if TOTP is enabled for an account.
  """
  @spec enabled?(Account.t()) :: boolean()
  def enabled?(%Account{totp_enabled_at: nil}), do: false
  def enabled?(%Account{totp_enabled_at: _}), do: true

  @doc """
  Get the decrypted TOTP secret for an account.
  """
  @spec get_secret(Account.t()) :: {:ok, binary()} | {:error, :totp_not_enabled}
  def get_secret(%Account{totp_secret_encrypted: nil}), do: {:error, :totp_not_enabled}

  def get_secret(%Account{totp_secret_encrypted: encrypted}) do
    {:ok, Vault.decrypt!(encrypted)}
  end

  @doc """
  Verify a TOTP or backup code for an account during login.

  Returns:
  - `{:ok, :totp}` if TOTP code was valid
  - `{:ok, :backup}` if backup code was valid (also updates account to remove used code)
  - `{:error, :invalid_code}` if neither was valid
  """
  @spec verify_login_code(Account.t(), String.t()) ::
          {:ok, :totp | :backup} | {:error, :invalid_code}
  def verify_login_code(account, code) do
    with {:ok, secret} <- get_secret(account) do
      # Try TOTP first
      case validate_code(secret, code) do
        :ok ->
          {:ok, :totp}

        {:error, :invalid_code} ->
          # Try backup code
          case verify_backup_code(code, account.backup_codes_hashed || []) do
            {:ok, remaining_codes} ->
              # Update account with remaining backup codes
              account
              |> Ecto.Changeset.change(%{backup_codes_hashed: remaining_codes})
              |> Repo.update()

              {:ok, :backup}

            {:error, :invalid_code} ->
              {:error, :invalid_code}
          end
      end
    end
  end

  @doc """
  Count remaining backup codes for an account.
  """
  @spec remaining_backup_codes(Account.t()) :: non_neg_integer()
  def remaining_backup_codes(%Account{backup_codes_hashed: nil}), do: 0
  def remaining_backup_codes(%Account{backup_codes_hashed: codes}), do: length(codes)

  # Generate a human-readable backup code (8 chars, uppercase alphanumeric)
  defp generate_backup_code do
    alphabet = ~c"ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"

    1..8
    |> Enum.map(fn _ -> Enum.random(alphabet) end)
    |> List.to_string()
    |> String.to_charlist()
    |> Enum.chunk_every(4)
    |> Enum.map(&List.to_string/1)
    |> Enum.join("-")
  end

  # Normalize backup code input (remove spaces/dashes, uppercase)
  defp normalize_backup_code(code) do
    code
    |> String.replace(~r/[\s\-]/, "")
    |> String.upcase()
  end

  # Generate QR code SVG from URI
  defp generate_qr_svg(uri) do
    uri
    |> EQRCode.encode()
    |> EQRCode.svg(width: 200)
  end
end
