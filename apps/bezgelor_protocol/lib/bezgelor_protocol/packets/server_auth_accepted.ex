defmodule BezgelorProtocol.Packets.ServerAuthAccepted do
  @moduledoc """
  Server authentication accepted response packet.

  Sent when client successfully authenticates via SRP6.

  ## Fields

  - `server_proof_m2` - SRP6 server evidence M2 (32 bytes SHA256)
  - `game_token` - Game token GUID for Auth Server (16 bytes)

  ## Wire Format

  ```
  server_proof_m2: 32 bytes
  game_token:      16 bytes
  ```
  """

  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct [
    :server_proof_m2,
    :game_token
  ]

  @type t :: %__MODULE__{
          server_proof_m2: binary(),
          game_token: binary()
        }

  @impl true
  def opcode, do: :server_auth_accepted

  @impl true
  @spec write(t(), PacketWriter.t()) :: {:ok, PacketWriter.t()}
  def write(%__MODULE__{} = packet, writer) do
    writer =
      writer
      |> PacketWriter.write_bytes(packet.server_proof_m2)
      |> PacketWriter.write_bytes(packet.game_token)

    {:ok, writer}
  end
end
