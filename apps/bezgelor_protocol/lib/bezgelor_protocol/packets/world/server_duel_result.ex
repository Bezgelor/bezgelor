defmodule BezgelorProtocol.Packets.World.ServerDuelResult do
  @moduledoc """
  Duel result notification.

  ## Overview

  Sent to both duel participants when the duel ends.

  ## Wire Format

  ```
  winner_guid  : uint64  - GUID of the winner
  winner_name  : string  - Name of the winner
  loser_guid   : uint64  - GUID of the loser
  loser_name   : string  - Name of the loser
  reason       : uint8   - End reason (0=defeat, 1=flee, 2=forfeit, 3=timeout)
  ```
  """

  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  # Result reasons
  @reason_defeat 0
  @reason_flee 1
  @reason_forfeit 2
  @reason_timeout 3

  defstruct [:winner_guid, :winner_name, :loser_guid, :loser_name, :reason]

  @type reason :: :defeat | :flee | :forfeit | :timeout

  @type t :: %__MODULE__{
          winner_guid: non_neg_integer(),
          winner_name: String.t(),
          loser_guid: non_neg_integer(),
          loser_name: String.t(),
          reason: reason()
        }

  @impl true
  def opcode, do: :server_duel_result

  @impl true
  @spec write(t(), PacketWriter.t()) :: {:ok, PacketWriter.t()}
  def write(%__MODULE__{} = packet, writer) do
    reason_byte = reason_to_int(packet.reason)

    writer =
      writer
      |> PacketWriter.write_u64(packet.winner_guid)
      |> PacketWriter.write_wide_string(packet.winner_name)
      |> PacketWriter.write_u64(packet.loser_guid)
      |> PacketWriter.write_wide_string(packet.loser_name)
      |> PacketWriter.write_u8(reason_byte)

    {:ok, writer}
  end

  @doc """
  Create a victory result (opponent defeated).
  """
  @spec victory(non_neg_integer(), String.t(), non_neg_integer(), String.t()) :: t()
  def victory(winner_guid, winner_name, loser_guid, loser_name) do
    %__MODULE__{
      winner_guid: winner_guid,
      winner_name: winner_name,
      loser_guid: loser_guid,
      loser_name: loser_name,
      reason: :defeat
    }
  end

  @doc """
  Create a flee result (opponent left boundary).
  """
  @spec flee(non_neg_integer(), String.t(), non_neg_integer(), String.t()) :: t()
  def flee(winner_guid, winner_name, loser_guid, loser_name) do
    %__MODULE__{
      winner_guid: winner_guid,
      winner_name: winner_name,
      loser_guid: loser_guid,
      loser_name: loser_name,
      reason: :flee
    }
  end

  @doc """
  Create a forfeit result (opponent gave up).
  """
  @spec forfeit(non_neg_integer(), String.t(), non_neg_integer(), String.t()) :: t()
  def forfeit(winner_guid, winner_name, loser_guid, loser_name) do
    %__MODULE__{
      winner_guid: winner_guid,
      winner_name: winner_name,
      loser_guid: loser_guid,
      loser_name: loser_name,
      reason: :forfeit
    }
  end

  @doc """
  Create a timeout result (time limit reached).
  """
  @spec timeout(non_neg_integer(), String.t(), non_neg_integer(), String.t()) :: t()
  def timeout(winner_guid, winner_name, loser_guid, loser_name) do
    %__MODULE__{
      winner_guid: winner_guid,
      winner_name: winner_name,
      loser_guid: loser_guid,
      loser_name: loser_name,
      reason: :timeout
    }
  end

  defp reason_to_int(:defeat), do: @reason_defeat
  defp reason_to_int(:flee), do: @reason_flee
  defp reason_to_int(:forfeit), do: @reason_forfeit
  defp reason_to_int(:timeout), do: @reason_timeout
  defp reason_to_int(_), do: @reason_defeat
end
