defmodule BezgelorProtocol.Packets.World.ClientNonSpellActionSetChanges do
  @moduledoc """
  Client request to update a non-spell action set shortcut.
  """

  @behaviour BezgelorProtocol.Packet.Readable

  alias BezgelorProtocol.PacketReader

  defstruct [:action_bar_index, :shortcut_type, :object_id, :spec_index]

  @type t :: %__MODULE__{
          action_bar_index: non_neg_integer(),
          shortcut_type: non_neg_integer(),
          object_id: non_neg_integer(),
          spec_index: non_neg_integer()
        }

  @impl true
  def opcode, do: :client_non_spell_action_set_changes

  @impl true
  @spec read(PacketReader.t()) :: {:ok, t(), PacketReader.t()} | {:error, term()}
  def read(reader) do
    with {:ok, action_bar_index, reader} <- PacketReader.read_bits(reader, 6),
         {:ok, shortcut_type, reader} <- PacketReader.read_bits(reader, 4),
         {:ok, object_id, reader} <- PacketReader.read_bits(reader, 32),
         {:ok, spec_index, reader} <- PacketReader.read_bits(reader, 4) do
      packet = %__MODULE__{
        action_bar_index: action_bar_index,
        shortcut_type: shortcut_type,
        object_id: object_id,
        spec_index: spec_index
      }

      {:ok, packet, reader}
    end
  end
end
