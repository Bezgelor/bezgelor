defmodule BezgelorProtocol.Packets.World.ServerAccountTier do
  @moduledoc """
  Server packet indicating the account tier (subscription level).

  ## Overview

  Sent before the character list to inform the client of the account's
  subscription tier. This affects available features and character slots.

  ## Account Tiers

  - 0: Free
  - 1: Basic/Signature (subscriber)
  - Other values may exist for special tiers

  ## Packet Structure (bit-packed)

  ```
  tier : 5 bits - Account tier value
  ```
  """

  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  # Account tier values
  @tier_free 0
  @tier_signature 1

  defstruct tier: @tier_signature

  @type t :: %__MODULE__{
          tier: non_neg_integer()
        }

  @impl true
  def opcode, do: :server_account_tier

  @impl true
  @spec write(t(), PacketWriter.t()) :: {:ok, PacketWriter.t()}
  def write(%__MODULE__{} = packet, writer) do
    writer =
      writer
      |> PacketWriter.write_bits(packet.tier, 5)
      |> PacketWriter.flush_bits()

    {:ok, writer}
  end

  @doc "Free tier constant"
  def tier_free, do: @tier_free

  @doc "Signature/subscriber tier constant"
  def tier_signature, do: @tier_signature
end
