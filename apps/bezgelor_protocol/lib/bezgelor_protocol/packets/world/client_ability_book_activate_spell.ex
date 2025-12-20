defmodule BezgelorProtocol.Packets.World.ClientAbilityBookActivateSpell do
  @moduledoc """
  Client request to toggle ability book spell activation.
  """

  @behaviour BezgelorProtocol.Packet.Readable

  alias BezgelorProtocol.PacketReader

  defstruct [:spell_id, :active]

  @type t :: %__MODULE__{
          spell_id: non_neg_integer(),
          active: boolean()
        }

  @impl true
  def opcode, do: :client_ability_book_activate_spell

  @impl true
  @spec read(PacketReader.t()) :: {:ok, t(), PacketReader.t()} | {:error, term()}
  def read(reader) do
    with {:ok, spell_id, reader} <- PacketReader.read_bits(reader, 18),
         {:ok, active, reader} <- PacketReader.read_bits(reader, 1) do
      packet = %__MODULE__{
        spell_id: spell_id,
        active: active == 1
      }

      {:ok, packet, reader}
    end
  end
end
