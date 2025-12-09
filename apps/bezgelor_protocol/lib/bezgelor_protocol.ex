defmodule BezgelorProtocol do
  @moduledoc """
  WildStar network protocol implementation.

  This application handles the low-level network protocol used by WildStar clients,
  including:

  - TCP connection management via Ranch
  - Packet framing (6-byte header: 4-byte size + 2-byte opcode)
  - Binary serialization/deserialization with bit-level precision
  - Packet encryption/decryption state machine
  - Message routing and handler dispatch

  ## Architecture

  The protocol layer sits between raw TCP sockets and game logic:

      Client <-> TCP (Ranch) <-> Connection <-> PacketReader/Writer <-> Handlers
  """

  @version Mix.Project.config()[:version]

  @doc """
  Returns the current version of the protocol library.
  """
  @spec version() :: String.t()
  def version, do: @version
end
