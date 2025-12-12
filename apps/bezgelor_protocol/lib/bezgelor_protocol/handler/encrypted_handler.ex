defmodule BezgelorProtocol.Handler.EncryptedHandler do
  @moduledoc """
  Handles encrypted packets (opcode 0x0077 - ClientEncrypted).

  Decrypts the payload using the session encryption cipher,
  then dispatches the inner packet to the appropriate handler.

  ## Encryption Flow

  1. Client sends encrypted packet with opcode 0x0077
  2. Handler retrieves cipher from connection state
  3. Payload is decrypted using PacketCrypt
  4. Inner opcode is extracted from decrypted data
  5. Inner packet is dispatched to appropriate handler

  ## State Requirements

  The connection state must contain:
  - `:packet_cipher` - A `BezgelorCrypto.PacketCrypt` struct initialized
    with the session key during authentication
  """

  @behaviour BezgelorProtocol.Handler

  alias BezgelorCrypto.PacketCrypt
  alias BezgelorProtocol.{Opcode, PacketReader, PacketRegistry}

  require Logger

  @impl true
  def handle(payload, state) do
    case decrypt_and_dispatch(payload, state) do
      {:ok, new_state} ->
        {:ok, new_state}

      {:error, reason} ->
        Logger.warning("EncryptedHandler: failed to process - #{inspect(reason)}")
        {:ok, state}
    end
  end

  defp decrypt_and_dispatch(payload, state) do
    # Get cipher from connection state
    cipher = Map.get(state, :packet_cipher)

    if is_nil(cipher) do
      Logger.warning("EncryptedHandler: no encryption cipher available")
      {:error, :no_cipher}
    else
      with {:ok, decrypted} <- decrypt_payload(cipher, payload),
           {:ok, inner_opcode, inner_payload} <- parse_inner_packet(decrypted),
           {:ok, handler} <- lookup_handler(inner_opcode) do
        Logger.debug(
          "EncryptedHandler: dispatching #{inner_opcode} (#{byte_size(inner_payload)} bytes)"
        )

        handler.handle(inner_payload, state)
      end
    end
  end

  # Decrypt the encrypted payload
  defp decrypt_payload(cipher, payload) do
    try do
      decrypted = PacketCrypt.decrypt(cipher, payload)
      {:ok, decrypted}
    rescue
      e ->
        Logger.warning("EncryptedHandler: decryption failed - #{inspect(e)}")
        {:error, :decryption_failed}
    end
  end

  # Parse the inner packet to extract opcode and payload
  defp parse_inner_packet(decrypted) when byte_size(decrypted) < 2 do
    {:error, :packet_too_short}
  end

  defp parse_inner_packet(decrypted) do
    reader = PacketReader.new(decrypted)

    with {:ok, opcode_int, reader} <- PacketReader.read_uint16(reader),
         {:ok, opcode} <- Opcode.from_integer(opcode_int) do
      # Extract remaining bytes from reader
      %{data: data, byte_pos: pos} = reader
      inner_payload = binary_part(data, pos, byte_size(data) - pos)
      {:ok, opcode, inner_payload}
    else
      {:error, :unknown_opcode} ->
        # Try to extract opcode for logging
        <<opcode_int::little-16, _rest::binary>> = decrypted
        Logger.warning("EncryptedHandler: unknown inner opcode 0x#{Integer.to_string(opcode_int, 16)}")
        {:error, {:unknown_opcode, opcode_int}}

      error ->
        error
    end
  end

  # Look up the handler for the inner opcode
  defp lookup_handler(opcode) do
    case PacketRegistry.lookup(opcode) do
      nil ->
        Logger.warning("EncryptedHandler: no handler for inner opcode #{opcode}")
        {:error, {:no_handler, opcode}}

      handler ->
        {:ok, handler}
    end
  end
end
