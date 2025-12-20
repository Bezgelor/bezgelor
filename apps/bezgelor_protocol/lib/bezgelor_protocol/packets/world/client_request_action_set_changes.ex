defmodule BezgelorProtocol.Packets.World.ClientRequestActionSetChanges do
  @moduledoc """
  Client request to update a Limited Action Set (spells + amps).
  """

  @behaviour BezgelorProtocol.Packet.Readable

  alias BezgelorProtocol.PacketReader

  defmodule ActionTier do
    @moduledoc false

    defstruct [:action, :tier]

    @type t :: %__MODULE__{
            action: non_neg_integer(),
            tier: non_neg_integer()
          }
  end

  defstruct actions: [], action_tiers: [], action_set_index: 0, amps: []

  @type t :: %__MODULE__{
          actions: [non_neg_integer()],
          action_tiers: [ActionTier.t()],
          action_set_index: non_neg_integer(),
          amps: [non_neg_integer()]
        }

  @impl true
  def opcode, do: :client_request_action_set_changes

  @impl true
  @spec read(PacketReader.t()) :: {:ok, t(), PacketReader.t()} | {:error, term()}
  def read(reader) do
    with {:ok, action_count, reader} <- PacketReader.read_bits(reader, 4),
         {:ok, actions, reader} <- read_actions(reader, action_count),
         {:ok, action_set_index, reader} <- PacketReader.read_bits(reader, 3),
         {:ok, tier_count, reader} <- PacketReader.read_bits(reader, 5),
         {:ok, action_tiers, reader} <- read_action_tiers(reader, tier_count),
         {:ok, amp_count, reader} <- PacketReader.read_bits(reader, 7),
         {:ok, amps, reader} <- read_amps(reader, amp_count) do
      packet = %__MODULE__{
        actions: actions,
        action_tiers: action_tiers,
        action_set_index: action_set_index,
        amps: amps
      }

      {:ok, packet, reader}
    end
  end

  defp read_actions(reader, count) do
    Enum.reduce_while(1..count, {[], reader}, fn _i, {acc, reader} ->
      case PacketReader.read_bits(reader, 32) do
        {:ok, action, reader} -> {:cont, {[action | acc], reader}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:error, reason} -> {:error, reason}
      {actions, reader} -> {:ok, Enum.reverse(actions), reader}
    end
  end

  defp read_action_tiers(reader, count) do
    Enum.reduce_while(1..count, {[], reader}, fn _i, {acc, reader} ->
      with {:ok, action, reader} <- PacketReader.read_bits(reader, 18),
           {:ok, tier, reader} <- PacketReader.read_bits(reader, 8) do
        {:cont, {[%ActionTier{action: action, tier: tier} | acc], reader}}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:error, reason} -> {:error, reason}
      {tiers, reader} -> {:ok, Enum.reverse(tiers), reader}
    end
  end

  defp read_amps(reader, count) do
    Enum.reduce_while(1..count, {[], reader}, fn _i, {acc, reader} ->
      case PacketReader.read_bits(reader, 16) do
        {:ok, amp_id, reader} -> {:cont, {[amp_id | acc], reader}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:error, reason} -> {:error, reason}
      {amps, reader} -> {:ok, Enum.reverse(amps), reader}
    end
  end
end
