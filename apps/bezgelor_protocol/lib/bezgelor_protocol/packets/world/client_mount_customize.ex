defmodule BezgelorProtocol.Packets.World.ClientMountCustomize do
  @moduledoc """
  Mount customization request from client.

  ## Wire Format
  dye_count   : uint8          - Number of dye channels
  dyes        : uint32[count]  - Dye IDs for each channel
  flair_count : uint8          - Number of flair items
  flairs      : string[count]  - Flair item keys
  """

  @behaviour BezgelorProtocol.Packet.Readable

  alias BezgelorProtocol.PacketReader

  defstruct [:dyes, :flairs]

  @type t :: %__MODULE__{
          dyes: [non_neg_integer()],
          flairs: [String.t()]
        }

  @impl true
  def opcode, do: :client_mount_customize

  @impl true
  def read(reader) do
    with {:ok, dye_count, reader} <- PacketReader.read_byte(reader),
         {:ok, dyes, reader} <- read_dyes(reader, dye_count),
         {:ok, flair_count, reader} <- PacketReader.read_byte(reader),
         {:ok, flairs, reader} <- read_flairs(reader, flair_count) do
      {:ok, %__MODULE__{dyes: dyes, flairs: flairs}, reader}
    end
  end

  defp read_dyes(reader, 0), do: {:ok, [], reader}

  defp read_dyes(reader, count) do
    Enum.reduce_while(1..count, {:ok, [], reader}, fn _, {:ok, acc, r} ->
      case PacketReader.read_uint32(r) do
        {:ok, dye, r2} -> {:cont, {:ok, [dye | acc], r2}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, dyes, r} -> {:ok, Enum.reverse(dyes), r}
      error -> error
    end
  end

  defp read_flairs(reader, 0), do: {:ok, [], reader}

  defp read_flairs(reader, count) do
    Enum.reduce_while(1..count, {:ok, [], reader}, fn _, {:ok, acc, r} ->
      case PacketReader.read_string(r) do
        {:ok, flair, r2} -> {:cont, {:ok, [flair | acc], r2}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, flairs, r} -> {:ok, Enum.reverse(flairs), r}
      error -> error
    end
  end
end
