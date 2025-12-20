defmodule BezgelorAuth.Sts.Session do
  @moduledoc """
  STS session state management.

  Tracks session state through the authentication flow:
  1. None -> Connected (after /Sts/Connect)
  2. Connected -> LoginStart (after /Auth/LoginStart)
  3. LoginStart -> Authenticated (after /Auth/KeyData + /Auth/LoginFinish)
  """

  alias BezgelorCrypto.{SRP6, RC4}

  defstruct [
    :state,
    :account,
    :srp6_server,
    :session_key,
    :game_token,
    :game_token_raw,
    :client_encryption,
    :server_encryption
  ]

  @type session_state :: :none | :connected | :login_start | :authenticated
  @type t :: %__MODULE__{
          state: session_state(),
          account: map() | nil,
          srp6_server: map() | nil,
          session_key: binary() | nil,
          game_token: binary() | nil,
          game_token_raw: binary() | nil,
          client_encryption: term() | nil,
          server_encryption: term() | nil
        }

  @doc """
  Create a new session in the initial state.
  """
  @spec new() :: t()
  def new do
    %__MODULE__{
      state: :none,
      account: nil,
      srp6_server: nil,
      session_key: nil,
      game_token: nil,
      client_encryption: nil,
      server_encryption: nil
    }
  end

  @doc """
  Transition to connected state.
  """
  @spec connect(t()) :: t()
  def connect(session) do
    %{session | state: :connected}
  end

  @doc """
  Start login process with account data.
  Returns the session with SRP6 server state and the salt/B values to send to client.
  """
  @spec start_login(t(), map()) :: {:ok, t(), binary(), binary()} | {:error, term()}
  def start_login(session, account) do
    # Account stores salt and verifier as hex strings
    salt = Base.decode16!(account.salt, case: :mixed)
    verifier = Base.decode16!(account.verifier, case: :mixed)

    case SRP6.new_server(account.email, salt, verifier) do
      {:ok, server} ->
        {:ok, public_b, server} = SRP6.server_credentials(server)

        session = %{session | state: :login_start, account: account, srp6_server: server}

        {:ok, session, salt, public_b}
    end
  end

  @doc """
  Process key exchange - client sends A and M1, we verify and return M2.
  """
  @spec key_exchange(t(), binary(), binary()) :: {:ok, t(), binary()} | {:error, term()}
  def key_exchange(session, client_public_a, client_proof_m1) do
    server = session.srp6_server

    case SRP6.calculate_secret(server, client_public_a) do
      {:ok, server} ->
        {:ok, session_key, server} = SRP6.calculate_session_key(server)

        case SRP6.verify_client_evidence(server, client_proof_m1) do
          {:ok, server} ->
            {:ok, server_proof_m2} = SRP6.server_evidence(server)

            session = %{session | srp6_server: server, session_key: session_key}
            {:ok, session, server_proof_m2}

          {:error, :invalid_evidence} ->
            {:error, :invalid_proof}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Complete login and generate game token.
  """
  @spec finish_login(t()) :: {:ok, t()}
  def finish_login(session) do
    {guid_string, raw_hex} = generate_game_token()

    session = %{session | state: :authenticated, game_token: guid_string, game_token_raw: raw_hex}

    {:ok, session}
  end

  @doc """
  Get the game token GUID string for sending to client.
  """
  @spec get_game_token(t()) :: binary() | nil
  def get_game_token(session) do
    session.game_token
  end

  @doc """
  Get the raw bytes hex of the game token for database storage.
  This matches what the client will send back.
  """
  @spec get_game_token_raw(t()) :: binary() | nil
  def get_game_token_raw(session) do
    session.game_token_raw
  end

  @doc """
  Initialize RC4 encryption after successful key exchange.
  Creates separate cipher states for client (decrypt) and server (encrypt).
  """
  @spec init_encryption(t()) :: t()
  def init_encryption(%{session_key: key} = session) when is_binary(key) do
    require Logger
    Logger.debug("[STS] Initializing RC4 encryption with key: #{Base.encode16(key)}")

    %{session | client_encryption: RC4.init(key), server_encryption: RC4.init(key)}
  end

  @doc """
  Check if encryption is enabled for this session.
  """
  @spec encryption_enabled?(t()) :: boolean()
  def encryption_enabled?(%{client_encryption: enc}), do: enc != nil

  @doc """
  Decrypt data received from client.
  Returns decrypted data and updated session.
  """
  @spec decrypt(t(), binary()) :: {binary(), t()}
  def decrypt(%{client_encryption: nil} = session, data), do: {data, session}

  def decrypt(%{client_encryption: enc} = session, data) do
    {decrypted, new_enc} = RC4.decrypt(enc, data)
    {decrypted, %{session | client_encryption: new_enc}}
  end

  @doc """
  Encrypt data to send to client.
  Returns encrypted data and updated session.
  """
  @spec encrypt(t(), binary()) :: {binary(), t()}
  def encrypt(%{server_encryption: nil} = session, data), do: {data, session}

  def encrypt(%{server_encryption: enc} = session, data) do
    {encrypted, new_enc} = RC4.encrypt(enc, data)
    {encrypted, %{session | server_encryption: new_enc}}
  end

  # Generate a random game token
  # Returns {guid_string, raw_bytes_hex}
  # - guid_string is sent to client (e.g., "e88d09e6-eced-85e4-d577-13cb1b2ea955")
  # - raw_bytes_hex is stored in DB for matching client's response (e.g., "E6098DE8...")
  defp generate_game_token do
    bytes = :crypto.strong_rand_bytes(16)
    hex = Base.encode16(bytes, case: :lower)
    guid_string = format_as_guid(hex)

    # Convert GUID string to raw bytes format that client will send back
    # GUID byte ordering: first 3 parts are little-endian, last 2 are big-endian
    raw_hex = guid_to_raw_hex(guid_string)

    {guid_string, raw_hex}
  end

  defp format_as_guid(hex) do
    <<a::binary-size(8), b::binary-size(4), c::binary-size(4), d::binary-size(4),
      e::binary-size(12)>> = hex

    "#{a}-#{b}-#{c}-#{d}-#{e}"
  end

  # Convert GUID string to raw bytes hex (matching .NET Guid.ToByteArray())
  # GUID: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
  # Bytes: first 4 reversed, next 2 reversed, next 2 reversed, rest as-is
  defp guid_to_raw_hex(guid) do
    [p1, p2, p3, p4, p5] = String.split(guid, "-")

    # Reverse byte order for first 3 parts
    p1_bytes = reverse_hex_pairs(p1)
    p2_bytes = reverse_hex_pairs(p2)
    p3_bytes = reverse_hex_pairs(p3)

    # Last parts stay as-is
    String.upcase(p1_bytes <> p2_bytes <> p3_bytes <> p4 <> p5)
  end

  defp reverse_hex_pairs(hex) do
    hex
    |> String.graphemes()
    |> Enum.chunk_every(2)
    |> Enum.reverse()
    |> Enum.join()
  end
end
