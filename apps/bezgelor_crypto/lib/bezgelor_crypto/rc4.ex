defmodule BezgelorCrypto.RC4 do
  @moduledoc """
  RC4/ARC4 stream cipher implementation.

  RC4 is a symmetric stream cipher - the same key and state is used for both
  encryption and decryption. Each cipher instance maintains state that advances
  with each byte processed, so separate instances are needed for send/receive.

  Note: The Erlang crypto state is mutable - subsequent calls to crypto_update
  advance the internal state. We return the same state reference for API
  consistency but the state is modified in-place.

  ## Usage

      # Initialize with session key
      state = BezgelorCrypto.RC4.init(session_key)

      # Encrypt data (modifies state in-place)
      {encrypted, state} = BezgelorCrypto.RC4.crypt(state, plaintext)

      # Decrypt data (same operation)
      {decrypted, state} = BezgelorCrypto.RC4.crypt(state, ciphertext)
  """

  @type t :: :crypto.crypto_state()

  @doc """
  Initialize a new RC4 cipher state with the given key.
  """
  @spec init(binary()) :: t()
  def init(key) when is_binary(key) do
    # true = encrypt mode (same as decrypt for RC4)
    :crypto.crypto_init(:rc4, key, true)
  end

  @doc """
  Encrypt or decrypt data using RC4.

  Returns the processed data and the cipher state (state is mutable).
  RC4 is symmetric - encrypt and decrypt use the same operation.
  """
  @spec crypt(t(), binary()) :: {binary(), t()}
  def crypt(state, data) when is_binary(data) do
    result = :crypto.crypto_update(state, data)
    # State is mutable, but we return it for API consistency
    {result, state}
  end

  @doc """
  Encrypt data (alias for crypt/2 for clarity).
  """
  @spec encrypt(t(), binary()) :: {binary(), t()}
  def encrypt(state, data), do: crypt(state, data)

  @doc """
  Decrypt data (alias for crypt/2 for clarity).
  """
  @spec decrypt(t(), binary()) :: {binary(), t()}
  def decrypt(state, data), do: crypt(state, data)
end
