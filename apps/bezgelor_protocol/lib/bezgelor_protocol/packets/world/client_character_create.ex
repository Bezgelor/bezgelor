defmodule BezgelorProtocol.Packets.World.ClientCharacterCreate do
  @moduledoc """
  Character creation request.

  ## Overview

  Client requests creation of a new character. The CharacterCreationId references
  a CharacterCreate table entry that defines race, class, sex, and default appearance.
  Customizations are then applied on top.

  ## Wire Format (from NexusForever)

  ```
  character_creation_id : uint32      - References CharacterCreate table entry
  name                  : wide_string - Character name
  path                  : 3 bits      - Path ID (0-3)
  customisation_count   : uint32      - Number of customization entries
  labels                : uint32[]    - customisation_count label IDs
  values                : uint32[]    - customisation_count value IDs
  bone_count            : uint32      - Number of bone values
  bones                 : float32[]   - bone_count float values
  ```
  """

  @behaviour BezgelorProtocol.Packet.Readable

  alias BezgelorProtocol.PacketReader

  defstruct [
    :character_creation_id,
    :name,
    :path,
    labels: [],
    values: [],
    bones: []
  ]

  @type t :: %__MODULE__{
          character_creation_id: non_neg_integer(),
          name: String.t(),
          path: non_neg_integer(),
          labels: [non_neg_integer()],
          values: [non_neg_integer()],
          bones: [float()]
        }

  @impl true
  def opcode, do: :client_character_create

  require Logger

  @impl true
  def read(reader) do
    Logger.debug("ClientCharacterCreate: starting parse, data size=#{byte_size(reader.data)}")

    # NexusForever reads everything through the bit reader continuously.
    # Path (3 bits) and customisation_count (32 bits) are packed together
    # without byte alignment in between.
    with {:ok, character_creation_id, reader} <- PacketReader.read_uint32(reader),
         _ = Logger.debug("ClientCharacterCreate: character_creation_id=#{character_creation_id}"),
         {:ok, name, reader} <- PacketReader.read_wide_string(reader),
         _ = Logger.debug("ClientCharacterCreate: name=#{inspect(name)}"),
         {:ok, path, reader} <- PacketReader.read_bits(reader, 3),
         _ = Logger.debug("ClientCharacterCreate: path=#{path}"),
         # DO NOT reset_bits here - customisation_count continues from bit 3
         {:ok, customisation_count, reader} <- PacketReader.read_bits(reader, 32),
         _ = Logger.debug("ClientCharacterCreate: customisation_count=#{customisation_count}"),
         {:ok, labels, reader} <- read_uint32_array_bits(reader, customisation_count),
         _ = Logger.debug("ClientCharacterCreate: labels=#{inspect(labels)}"),
         {:ok, values, reader} <- read_uint32_array_bits(reader, customisation_count),
         _ = Logger.debug("ClientCharacterCreate: values=#{inspect(values)}"),
         {:ok, bone_count, reader} <- PacketReader.read_bits(reader, 32),
         _ = Logger.debug("ClientCharacterCreate: bone_count=#{bone_count}"),
         {:ok, bones, reader} <- read_float_array_bits(reader, bone_count) do
      packet = %__MODULE__{
        character_creation_id: character_creation_id,
        name: name,
        path: path,
        labels: labels,
        values: values,
        bones: bones
      }

      Logger.debug("ClientCharacterCreate: parsed successfully")
      {:ok, packet, reader}
    else
      error ->
        Logger.warning("ClientCharacterCreate: parse failed at step, error=#{inspect(error)}")
        error
    end
  end

  # Bit-based array reading - continues from current bit position
  defp read_uint32_array_bits(reader, 0), do: {:ok, [], reader}

  defp read_uint32_array_bits(reader, count) do
    read_uint32_array_bits(reader, count, [])
  end

  defp read_uint32_array_bits(reader, 0, acc), do: {:ok, Enum.reverse(acc), reader}

  defp read_uint32_array_bits(reader, remaining, acc) do
    with {:ok, value, reader} <- PacketReader.read_bits(reader, 32) do
      read_uint32_array_bits(reader, remaining - 1, [value | acc])
    end
  end

  defp read_float_array_bits(reader, 0), do: {:ok, [], reader}

  defp read_float_array_bits(reader, count) do
    read_float_array_bits(reader, count, [])
  end

  defp read_float_array_bits(reader, 0, acc), do: {:ok, Enum.reverse(acc), reader}

  defp read_float_array_bits(reader, remaining, acc) do
    # Read 32 bits and convert to IEEE 754 float
    with {:ok, bits, reader} <- PacketReader.read_bits(reader, 32) do
      float_value = bits_to_float32(bits)
      read_float_array_bits(reader, remaining - 1, [float_value | acc])
    end
  end

  # Convert 32-bit integer to IEEE 754 single-precision float
  defp bits_to_float32(bits) when is_integer(bits) do
    <<float::float-32-native>> = <<bits::32-native>>
    float
  end

  @doc """
  Convert customization data to database-compatible map.

  Labels and values are stored as arrays for sending back in character list.
  Also stored as a map for potential future use.
  """
  @spec customization_to_map(t()) :: map()
  def customization_to_map(%__MODULE__{} = packet) do
    customizations =
      Enum.zip(packet.labels, packet.values)
      |> Enum.into(%{}, fn {label, value} -> {label, value} end)

    %{
      customizations: customizations,
      labels: packet.labels,
      values: packet.values,
      bones: packet.bones
    }
  end
end
