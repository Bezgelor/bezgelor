defmodule BezgelorProtocol.Packets.World.ClientHelloRealm do
  @moduledoc """
  Client authentication for world server.

  ## Overview

  Sent when connecting to the world server after realm selection.
  Contains session key from realm server for validation.

  ## Wire Format

  ```
  account_id    : uint32
  session_key   : 16 bytes
  email         : wide_string (length-prefixed UTF-16LE)
  ```

  The session key was provided by the realm server in ServerRealmInfo
  and must match the stored session key for this account.
  """

  @behaviour BezgelorProtocol.Packet.Readable

  alias BezgelorProtocol.PacketReader

  defstruct [
    :account_id,
    :session_key,
    :email
  ]

  @type t :: %__MODULE__{
          account_id: non_neg_integer(),
          session_key: binary(),
          email: String.t()
        }

  @impl true
  def opcode, do: :client_hello_realm

  @impl true
  def read(reader) do
    with {:ok, account_id, reader} <- PacketReader.read_uint32(reader),
         {:ok, session_key, reader} <- PacketReader.read_bytes(reader, 16),
         {:ok, email, reader} <- PacketReader.read_wide_string(reader) do
      packet = %__MODULE__{
        account_id: account_id,
        session_key: session_key,
        email: email
      }

      {:ok, packet, reader}
    end
  end
end
