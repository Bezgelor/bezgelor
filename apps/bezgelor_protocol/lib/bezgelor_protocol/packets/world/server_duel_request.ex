defmodule BezgelorProtocol.Packets.World.ServerDuelRequest do
  @moduledoc """
  Incoming duel challenge notification.

  ## Overview

  Sent to a player when another player challenges them to a duel.
  The receiver should respond with ClientDuelResponse.

  ## Wire Format

  ```
  challenger_guid : uint64  - GUID of the challenger
  challenger_name : string  - Name of the challenger
  timeout_seconds : uint16  - Seconds until challenge expires
  ```
  """

  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct [:challenger_guid, :challenger_name, :timeout_seconds]

  @type t :: %__MODULE__{
          challenger_guid: non_neg_integer(),
          challenger_name: String.t(),
          timeout_seconds: non_neg_integer()
        }

  @impl true
  def opcode, do: :server_duel_request

  @impl true
  @spec write(t(), PacketWriter.t()) :: {:ok, PacketWriter.t()}
  def write(%__MODULE__{} = packet, writer) do
    writer =
      writer
      |> PacketWriter.write_uint64(packet.challenger_guid)
      |> PacketWriter.write_wide_string(packet.challenger_name)
      |> PacketWriter.write_uint16(packet.timeout_seconds)

    {:ok, writer}
  end

  @doc """
  Create a duel request notification.
  """
  @spec new(non_neg_integer(), String.t(), non_neg_integer()) :: t()
  def new(challenger_guid, challenger_name, timeout_seconds \\ 30) do
    %__MODULE__{
      challenger_guid: challenger_guid,
      challenger_name: challenger_name,
      timeout_seconds: timeout_seconds
    }
  end
end
