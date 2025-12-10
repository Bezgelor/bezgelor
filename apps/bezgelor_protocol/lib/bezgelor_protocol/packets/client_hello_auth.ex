defmodule BezgelorProtocol.Packets.ClientHelloAuth do
  @moduledoc """
  Client authentication request packet.

  Sent by client after receiving ServerHello. Contains SRP6 credentials
  for authentication.

  ## Fields

  - `build` - Client build version (must be 16042)
  - `email` - Account email address
  - `client_key_a` - SRP6 public key A (128 bytes)
  - `client_proof_m1` - SRP6 client evidence M1 (32 bytes SHA256)

  ## Wire Format

  ```
  build:          uint32 (little-endian)
  email:          wide_string (uint32 length + UTF-16LE)
  client_key_a:   128 bytes
  client_proof_m1: 32 bytes
  ```
  """

  @behaviour BezgelorProtocol.Packet.Readable

  alias BezgelorProtocol.PacketReader

  @client_key_size 128
  @proof_size 32

  defstruct [
    :build,
    :email,
    :client_key_a,
    :client_proof_m1
  ]

  @type t :: %__MODULE__{
          build: non_neg_integer(),
          email: String.t(),
          client_key_a: binary(),
          client_proof_m1: binary()
        }

  @impl true
  def opcode, do: :client_hello_auth

  @impl true
  @spec read(PacketReader.t()) :: {:ok, t(), PacketReader.t()} | {:error, term()}
  def read(reader) do
    with {:ok, build, reader} <- PacketReader.read_uint32(reader),
         {:ok, email, reader} <- PacketReader.read_wide_string(reader),
         {:ok, client_key_a, reader} <- PacketReader.read_bytes(reader, @client_key_size),
         {:ok, client_proof_m1, reader} <- PacketReader.read_bytes(reader, @proof_size) do
      packet = %__MODULE__{
        build: build,
        email: email,
        client_key_a: client_key_a,
        client_proof_m1: client_proof_m1
      }

      {:ok, packet, reader}
    end
  end
end
