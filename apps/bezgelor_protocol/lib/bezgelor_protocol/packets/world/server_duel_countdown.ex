defmodule BezgelorProtocol.Packets.World.ServerDuelCountdown do
  @moduledoc """
  Duel countdown notification.

  ## Overview

  Sent to both duel participants when the countdown begins
  after a duel is accepted.

  ## Wire Format

  ```
  opponent_guid    : uint64  - GUID of opponent
  opponent_name    : string  - Name of opponent
  countdown_seconds: uint8   - Seconds until duel starts
  center_x         : float32 - Center X of duel boundary
  center_y         : float32 - Center Y of duel boundary
  center_z         : float32 - Center Z of duel boundary
  radius           : float32 - Duel boundary radius
  ```
  """

  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct [:opponent_guid, :opponent_name, :countdown_seconds, :center, :radius]

  @type t :: %__MODULE__{
          opponent_guid: non_neg_integer(),
          opponent_name: String.t(),
          countdown_seconds: non_neg_integer(),
          center: {float(), float(), float()},
          radius: float()
        }

  @impl true
  def opcode, do: :server_duel_countdown

  @impl true
  @spec write(t(), PacketWriter.t()) :: {:ok, PacketWriter.t()}
  def write(%__MODULE__{} = packet, writer) do
    {cx, cy, cz} = packet.center

    writer =
      writer
      |> PacketWriter.write_u64(packet.opponent_guid)
      |> PacketWriter.write_wide_string(packet.opponent_name)
      |> PacketWriter.write_u8(packet.countdown_seconds)
      |> PacketWriter.write_f32(cx)
      |> PacketWriter.write_f32(cy)
      |> PacketWriter.write_f32(cz)
      |> PacketWriter.write_f32(packet.radius)

    {:ok, writer}
  end

  @doc """
  Create a duel countdown notification.
  """
  @spec new(non_neg_integer(), String.t(), non_neg_integer(), {float(), float(), float()}, float()) ::
          t()
  def new(opponent_guid, opponent_name, countdown_seconds, center, radius) do
    %__MODULE__{
      opponent_guid: opponent_guid,
      opponent_name: opponent_name,
      countdown_seconds: countdown_seconds,
      center: center,
      radius: radius
    }
  end
end
