defmodule BezgelorProtocol.Packets.World.ServerAccountEntitlements do
  @moduledoc """
  Server packet containing the account's entitlements.

  ## Overview

  Sent before the character list to inform the client of the account's
  entitlements (unlocked features, bonuses, etc.).

  ## Packet Structure

  ```
  count        : uint32           - Number of entitlements
  entitlements : Entitlement[]    - Array of entitlements
  ```

  ## Entitlement Structure

  ```
  type  : uint32 (32 bits) - Entitlement type ID
  count : uint32           - Amount/count of this entitlement
  ```
  """

  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defmodule Entitlement do
    @moduledoc """
    An individual account entitlement.
    """
    defstruct type: 0,
              count: 0

    @type t :: %__MODULE__{
            type: non_neg_integer(),
            count: non_neg_integer()
          }
  end

  defstruct entitlements: []

  @type t :: %__MODULE__{
          entitlements: [Entitlement.t()]
        }

  @impl true
  def opcode, do: :server_account_entitlements

  @impl true
  @spec write(t(), PacketWriter.t()) :: {:ok, PacketWriter.t()}
  def write(%__MODULE__{} = packet, writer) do
    entitlements = packet.entitlements || []

    # Write count
    writer = PacketWriter.write_uint32(writer, length(entitlements))

    # Write each entitlement
    writer =
      Enum.reduce(entitlements, writer, fn ent, w ->
        w
        |> PacketWriter.write_bits(ent.type, 32)
        |> PacketWriter.write_bits(ent.count, 32)
      end)

    writer = PacketWriter.flush_bits(writer)

    {:ok, writer}
  end

  @doc """
  Create a default entitlements packet with common entitlements for signature tier.
  """
  def default_entitlements do
    %__MODULE__{
      entitlements: [
        # Common entitlements for signature/subscriber accounts
        # EntitlementType.BaseCharacterSlots = 6 slots
        %Entitlement{type: 0, count: 6},
        # EntitlementType.ExtraDecorSlots = 1000
        %Entitlement{type: 2, count: 1000}
      ]
    }
  end
end
