defmodule BezgelorProtocol.Handler.EncryptedHandler do
  @moduledoc """
  Handles encrypted packets (opcode 0x0244 - ClientEncrypted).

  Decrypts the payload using the session encryption cipher,
  then dispatches the inner packet to the appropriate handler.

  ## Encryption Flow

  1. Client sends encrypted packet with opcode 0x0244
  2. Handler retrieves cipher from connection state
  3. Payload is decrypted using PacketCrypt
  4. Inner opcode is extracted from decrypted data
  5. Inner packet is dispatched to appropriate handler

  ## State Requirements

  The connection state must contain:
  - `:encryption` - A `BezgelorCrypto.PacketCrypt` struct initialized
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

      {:reply, opcode, response, new_state} ->
        {:reply, opcode, response, new_state}

      {:reply_encrypted, opcode, response, new_state} ->
        {:reply_encrypted, opcode, response, new_state}

      {:reply_multi, responses, new_state} ->
        {:reply_multi, responses, new_state}

      {:reply_multi_encrypted, responses, new_state} ->
        {:reply_multi_encrypted, responses, new_state}

      {:reply_world_encrypted, opcode, response, new_state} ->
        {:reply_world_encrypted, opcode, response, new_state}

      {:reply_multi_world_encrypted, responses, new_state} ->
        {:reply_multi_world_encrypted, responses, new_state}

      {:error, reason} ->
        Logger.warning("EncryptedHandler: failed to process - #{inspect(reason)}")
        {:ok, state}
    end
  end

  defp decrypt_and_dispatch(payload, state) do
    # Get cipher from connection state (stored as :encryption in Connection struct)
    cipher = Map.get(state, :encryption)

    if is_nil(cipher) do
      Logger.warning("EncryptedHandler: no encryption cipher available")
      {:error, :no_cipher}
    else
      # ClientEncrypted packet structure: uint32 length + encrypted_data
      # The length includes itself, so encrypted_data = length - 4 bytes
      with {:ok, encrypted_data} <- extract_encrypted_data(payload),
           {:ok, decrypted} <- decrypt_payload(cipher, encrypted_data),
           {:ok, inner_opcode, inner_payload} <- parse_inner_packet(decrypted),
           {:ok, handler} <- lookup_handler(inner_opcode) do
        # Log with same format as Connection - shows the actual opcode being handled
        server_name = server_name_from_state(state)
        Logger.debug("[#{server_name}] Recv: #{Opcode.name(inner_opcode)} (#{byte_size(inner_payload)} bytes)")

        handler.handle(inner_payload, state)
      end
    end
  end

  defp server_name_from_state(%{connection_type: :realm}), do: "Realm"
  defp server_name_from_state(%{connection_type: :world}), do: "World"
  defp server_name_from_state(_), do: "Unknown"

  # Extract encrypted data from ClientEncrypted packet (skip 4-byte length prefix)
  defp extract_encrypted_data(payload) when byte_size(payload) < 4 do
    {:error, :payload_too_short}
  end

  defp extract_encrypted_data(payload) do
    <<length::little-32, rest::binary>> = payload
    # Length includes itself (4 bytes), so encrypted data is (length - 4) bytes
    encrypted_data_size = length - 4

    if byte_size(rest) < encrypted_data_size do
      Logger.warning("EncryptedHandler: payload too short. Expected #{encrypted_data_size} bytes, got #{byte_size(rest)}")
      {:error, :payload_too_short}
    else
      encrypted_data = binary_part(rest, 0, encrypted_data_size)
      {:ok, encrypted_data}
    end
  end

  # Decrypt the encrypted payload
  defp decrypt_payload(cipher, payload) do
    case PacketCrypt.decrypt(cipher, payload) do
      {:ok, decrypted} ->
        {:ok, decrypted}

      {:error, reason} ->
        Logger.warning("EncryptedHandler: decryption failed - #{inspect(reason)}")
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
