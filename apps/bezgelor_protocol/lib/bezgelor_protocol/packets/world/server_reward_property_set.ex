defmodule BezgelorProtocol.Packets.World.ServerRewardPropertySet do
  @moduledoc """
  Server packet containing reward properties for the account.

  ## Overview

  Sent to inform the client about account reward properties like
  character slots, bank slots, etc. These values are derived from
  the account's tier and entitlements.

  ## Packet Structure

  ```
  count      : uint8           - Number of properties
  properties : RewardProperty[] - Property entries
  ```

  ## RewardProperty Structure

  ```
  id         : 6 bits  - RewardPropertyType
  data       : uint32  - Additional data (usually 0)
  type       : 2 bits  - Value type (0=additive scalar, 1=discrete, 2=multiplicative scalar)
  value      : varies  - float for types 0/2, uint32 for type 1
  sub_count  : 8 bits  - Sub-property count (usually 0)
  ```

  ## Common RewardPropertyTypes

  - 29: CharacterSlots - Number of character slots available
  """

  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  # RewardPropertyType values
  @character_slots 29

  # RewardPropertyModifierValueType
  @additive_scalar 0
  @discrete 1
  @multiplicative_scalar 2

  defstruct properties: []

  defmodule RewardProperty do
    @moduledoc """
    A single reward property entry.
    """
    defstruct id: 0,
              data: 0,
              type: 1,
              value: 0

    @type t :: %__MODULE__{
            id: non_neg_integer(),
            data: non_neg_integer(),
            type: non_neg_integer(),
            value: number()
          }
  end

  @type t :: %__MODULE__{
          properties: [RewardProperty.t()]
        }

  @impl true
  def opcode, do: :server_reward_property_set

  @impl true
  @spec write(t(), PacketWriter.t()) :: {:ok, PacketWriter.t()}
  def write(%__MODULE__{} = packet, writer) do
    # Property count (8 bits) - all bit-packed, no alignment
    writer = PacketWriter.write_bits(writer, length(packet.properties), 8)

    # Write each property (continuous bit stream)
    writer = Enum.reduce(packet.properties, writer, &write_property/2)

    # Flush at the end
    writer = PacketWriter.flush_bits(writer)

    {:ok, writer}
  end

  defp write_property(prop, writer) do
    # All fields are bit-packed continuously (no byte alignment)
    # ID (6 bits)
    writer = PacketWriter.write_bits(writer, prop.id, 6)

    # Data (32 bits)
    writer = PacketWriter.write_bits(writer, prop.data, 32)

    # Type (2 bits)
    writer = PacketWriter.write_bits(writer, prop.type, 2)

    # Value (32 bits) - depends on type
    writer =
      case prop.type do
        @additive_scalar ->
          # Float value
          PacketWriter.write_f32(writer, prop.value)

        @discrete ->
          # Uint32 value
          PacketWriter.write_bits(writer, trunc(prop.value), 32)

        @multiplicative_scalar ->
          # Float value
          PacketWriter.write_f32(writer, prop.value)

        _ ->
          # Default to discrete
          PacketWriter.write_bits(writer, trunc(prop.value), 32)
      end

    # Sub-property count (8 bits) - we don't use sub-properties
    PacketWriter.write_bits(writer, 0, 8)
  end

  @doc """
  Create a packet with character slots property.
  """
  @spec with_character_slots(non_neg_integer()) :: t()
  def with_character_slots(slots) do
    %__MODULE__{
      properties: [
        %RewardProperty{
          id: @character_slots,
          data: 0,
          type: @discrete,
          value: slots
        }
      ]
    }
  end

  # Export constants for external use
  def character_slots_type, do: @character_slots
  def discrete_type, do: @discrete
end
