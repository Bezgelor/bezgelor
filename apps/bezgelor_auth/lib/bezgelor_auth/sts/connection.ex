defmodule BezgelorAuth.Sts.Connection do
  @moduledoc """
  STS protocol connection handler.

  Handles the STS/1.0 protocol for WildStar client authentication.
  Uses Ranch for TCP connection management.
  """

  use GenServer
  require Logger

  alias BezgelorAuth.Sts.{Packet, Session, Handler}

  @behaviour :ranch_protocol

  defstruct [
    :socket,
    :transport,
    :buffer,
    :session,
    :client_addr
  ]

  # Ranch protocol callback
  @impl :ranch_protocol
  def start_link(ref, transport, opts) do
    pid = :proc_lib.spawn_link(__MODULE__, :ranch_init, [{ref, transport, opts}])
    {:ok, pid}
  end

  @impl GenServer
  def init(_), do: {:stop, :not_used}

  @doc false
  def ranch_init({ref, transport, _opts}) do
    {:ok, socket} = :ranch.handshake(ref)
    :ok = transport.setopts(socket, [{:active, :once}, {:packet, :raw}, :binary])

    {:ok, {client_ip, client_port}} = :inet.peername(socket)
    client_addr = "#{:inet.ntoa(client_ip)}:#{client_port}"

    Logger.info("[STS] New connection from #{client_addr}")

    state = %__MODULE__{
      socket: socket,
      transport: transport,
      buffer: <<>>,
      session: Session.new(),
      client_addr: client_addr
    }

    :gen_server.enter_loop(__MODULE__, [], state)
  end

  @impl GenServer
  def handle_info({:tcp, socket, data}, %{socket: socket, buffer: buffer} = state) do
    state.transport.setopts(socket, [{:active, :once}])

    new_buffer = buffer <> data
    state = %{state | buffer: new_buffer}

    case process_buffer(state) do
      {:ok, state} ->
        {:noreply, state}

      {:error, reason} ->
        Logger.warning("[STS] Error processing request: #{inspect(reason)}")
        {:stop, :normal, state}
    end
  end

  def handle_info({:tcp_closed, socket}, %{socket: socket} = state) do
    Logger.debug("[STS] Connection closed by client (#{state.client_addr})")
    {:stop, :normal, state}
  end

  def handle_info({:tcp_error, socket, reason}, %{socket: socket} = state) do
    Logger.warning("[STS] TCP error: #{inspect(reason)} (#{state.client_addr})")
    {:stop, :normal, state}
  end

  # Process buffer for complete packets
  defp process_buffer(state) do
    # Decrypt buffer if encryption is enabled
    {buffer_to_parse, state} = maybe_decrypt_buffer(state)

    case Packet.parse_request(buffer_to_parse) do
      {:ok, packet, remaining} ->
        Logger.debug(
          "[STS] Recv: #{packet.method} #{packet.uri} (#{byte_size(packet.body)} bytes)"
        )

        {response, new_session, init_encryption} = Handler.handle(packet, state.session)

        # Encrypt response if encryption is CURRENTLY enabled on the connection.
        # On first login: connection is unencrypted, KeyData response sent unencrypted, then init encryption
        # On re-login: connection is already encrypted, KeyData response must be encrypted with OLD key
        # The key insight: check state.session (current state) not new_session (after handler)
        {response_to_send, new_session} =
          if response && Session.encryption_enabled?(state.session) do
            Session.encrypt(new_session, response)
          else
            {response, new_session}
          end

        # Send response
        send_result =
          if response_to_send do
            state.transport.send(state.socket, response_to_send)
          else
            :ok
          end

        case send_result do
          :ok ->
            # Initialize encryption AFTER sending the response (for KeyData)
            new_session =
              if init_encryption do
                Logger.debug("[STS] Enabling RC4 encryption")
                Session.init_encryption(new_session)
              else
                new_session
              end

            state = %{state | buffer: remaining, session: new_session}

            # Continue processing if there's more data
            if byte_size(remaining) > 0 do
              process_buffer(state)
            else
              {:ok, state}
            end

          {:error, reason} ->
            {:error, {:send_failed, reason}}
        end

      {:incomplete, _} ->
        {:ok, %{state | buffer: buffer_to_parse}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Decrypt buffer if encryption is enabled
  defp maybe_decrypt_buffer(%{session: session, buffer: buffer} = state) do
    if Session.encryption_enabled?(session) && byte_size(buffer) > 0 do
      {decrypted, new_session} = Session.decrypt(session, buffer)
      {decrypted, %{state | session: new_session, buffer: <<>>}}
    else
      {buffer, state}
    end
  end
end
