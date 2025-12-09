defmodule BezgelorCrypto.PacketCrypt do
  @moduledoc """
  WildStar packet encryption/decryption.

  ## Overview

  This module implements WildStar's packet encryption scheme, which uses
  a 1024-bit key derived from either:

  - The client build number (for auth server)
  - A session key ticket (for world server)

  The encryption is a custom XOR-based cipher that maintains state
  between operations.

  ## Example

      # Create cipher for auth server
      key = BezgelorCrypto.PacketCrypt.key_from_auth_build()
      crypt = BezgelorCrypto.PacketCrypt.new(key)

      # Encrypt outgoing packet
      encrypted = BezgelorCrypto.PacketCrypt.encrypt(crypt, packet_data)

      # Decrypt incoming packet
      decrypted = BezgelorCrypto.PacketCrypt.decrypt(crypt, incoming_data)
  """

  @crypt_multiplier 0xAA7F8EA9
  @crypt_multiplier_2 0xAA7F8EAA
  @crypt_initial_value 0x718DA9074F2DEB91

  defstruct [:key, :key_value]

  @type t :: %__MODULE__{
          key: binary(),
          key_value: non_neg_integer()
        }

  @doc """
  Create a new packet cipher from a key integer.

  The key integer is used to derive a 1024-bit encryption key.
  """
  @spec new(non_neg_integer()) :: t()
  def new(key_integer) when is_integer(key_integer) do
    {key, key_value} = derive_key(key_integer)
    %__MODULE__{key: key, key_value: key_value}
  end

  @doc """
  Decrypt a packet buffer.

  Note: This creates a new state buffer for each operation. The cipher
  state is not modified between calls.
  """
  @spec decrypt(t(), binary()) :: binary()
  def decrypt(%__MODULE__{key: key, key_value: key_value}, buffer) when is_binary(buffer) do
    length = byte_size(buffer)
    # State initialized from key_value, reversed byte order for decrypt
    state = <<key_value::little-64>> |> reverse_bytes()

    v4 = band(@crypt_multiplier_2 * length, 0xFFFFFFFF)

    {output, _state, _v4, _v9} =
      buffer
      |> :binary.bin_to_list()
      |> Enum.with_index()
      |> Enum.reduce({[], state, v4, 0}, fn {byte, i}, {acc, state, v4, v9} ->
        state_index = rem(i, 8)

        {v4, v9} =
          if state_index == 0 do
            {v4 + 1, band(v4, 0xF) * 8}
          else
            {v4, v9}
          end

        state_byte = :binary.at(state, 7 - state_index)
        key_byte = :binary.at(key, v9 + state_index)

        output_byte = bxor(bxor(state_byte, byte), key_byte) |> band(0xFF)

        # Update state with input byte (decrypt)
        new_state = replace_byte(state, 7 - state_index, byte)

        {[output_byte | acc], new_state, v4, v9}
      end)

    output |> Enum.reverse() |> :binary.list_to_bin()
  end

  @doc """
  Encrypt a packet buffer.
  """
  @spec encrypt(t(), binary()) :: binary()
  def encrypt(%__MODULE__{key: key, key_value: key_value}, buffer) when is_binary(buffer) do
    length = byte_size(buffer)
    # State initialized from key_value, normal byte order for encrypt
    state = <<key_value::little-64>>

    v4 = band(@crypt_multiplier_2 * length, 0xFFFFFFFF)

    {output, _state, _v4, _v9} =
      buffer
      |> :binary.bin_to_list()
      |> Enum.with_index()
      |> Enum.reduce({[], state, v4, 0}, fn {byte, i}, {acc, state, v4, v9} ->
        state_index = rem(i, 8)

        {v4, v9} =
          if state_index == 0 do
            {v4 + 1, band(v4, 0xF) * 8}
          else
            {v4, v9}
          end

        state_byte = :binary.at(state, state_index)
        key_byte = :binary.at(key, v9 + state_index)

        output_byte = bxor(bxor(state_byte, byte), key_byte) |> band(0xFF)

        # Update state with output byte (encrypt)
        new_state = replace_byte(state, state_index, output_byte)

        {[output_byte | acc], new_state, v4, v9}
      end)

    output |> Enum.reverse() |> :binary.list_to_bin()
  end

  @doc """
  Generate encryption key from client build and auth message.

  This is used for the auth server connection before session is established.
  Hardcoded for build 16042.
  """
  @spec key_from_auth_build() :: non_neg_integer()
  def key_from_auth_build do
    key = @crypt_initial_value + 0x5B88D61139619662
    key = band(key * @crypt_multiplier, 0xFFFFFFFFFFFFFFFF)
    key = band((key + 16042) * @crypt_multiplier, 0xFFFFFFFFFFFFFFFF)
    band((key + 0x97998A0) * @crypt_multiplier, 0xFFFFFFFFFFFFFFFF)
  end

  @doc """
  Generate encryption key from a session key ticket.

  This is used for world server connections after authentication.
  The session key must be exactly 16 bytes.
  """
  @spec key_from_ticket(binary()) :: non_neg_integer()
  def key_from_ticket(session_key) when is_binary(session_key) do
    if byte_size(session_key) != 16 do
      raise ArgumentError, "session key must be exactly 16 bytes"
    end

    key =
      session_key
      |> :binary.bin_to_list()
      |> Enum.reduce(@crypt_initial_value, fn byte, key ->
        band((key + byte) * @crypt_multiplier, 0xFFFFFFFFFFFFFFFF)
      end)

    band((key + key_from_auth_build()) * @crypt_multiplier, 0xFFFFFFFFFFFFFFFF)
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  # Exact port of C# key derivation loop
  defp derive_key(key_integer) do
    key_val = @crypt_initial_value
    v2 = band((key_val + key_integer) * @crypt_multiplier, 0xFFFFFFFFFFFFFFFF)

    {chunks, final_kv, _final_v2} =
      Enum.reduce(0..15, {[], key_val, v2}, fn _i, {acc, kv, v2} ->
        chunk = <<v2::little-64>>
        new_kv = band((kv + v2) * @crypt_multiplier, 0xFFFFFFFFFFFFFFFF)
        new_v2 = band((key_integer + v2) * @crypt_multiplier, 0xFFFFFFFFFFFFFFFF)
        {[chunk | acc], new_kv, new_v2}
      end)

    key = chunks |> Enum.reverse() |> IO.iodata_to_binary()
    {key, final_kv}
  end

  defp reverse_bytes(<<bytes::binary-size(8)>>) do
    bytes |> :binary.bin_to_list() |> Enum.reverse() |> :binary.list_to_bin()
  end

  defp replace_byte(binary, index, new_byte) do
    <<prefix::binary-size(index), _old::8, suffix::binary>> = binary
    <<prefix::binary, new_byte::8, suffix::binary>>
  end

  defp band(a, b), do: Bitwise.band(a, b)
  defp bxor(a, b), do: Bitwise.bxor(a, b)
end
