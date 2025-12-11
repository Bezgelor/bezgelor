defmodule BezgelorProtocol.Packets.World.ClientWarplotPlug do
  @moduledoc """
  Warplot plug management.

  ## Overview

  Sent when a player wants to install, remove, or upgrade
  a plug in their guild's warplot.

  ## Wire Format

  ```
  warplot_id : uint32  - Warplot ID
  socket_id  : uint8   - Socket position (1-8)
  action     : uint8   - 0=install, 1=remove, 2=upgrade
  plug_id    : uint32  - Plug type to install (only for install action)
  ```
  """

  @behaviour BezgelorProtocol.Packet.Readable

  alias BezgelorProtocol.PacketReader

  defstruct [:warplot_id, :socket_id, :action, :plug_id]

  @type action :: :install | :remove | :upgrade

  @type t :: %__MODULE__{
          warplot_id: non_neg_integer(),
          socket_id: non_neg_integer(),
          action: action(),
          plug_id: non_neg_integer() | nil
        }

  @impl true
  def opcode, do: :client_warplot_plug

  @impl true
  def read(reader) do
    with {:ok, warplot_id, reader} <- PacketReader.read_uint32(reader),
         {:ok, socket_id, reader} <- PacketReader.read_byte(reader),
         {:ok, action_byte, reader} <- PacketReader.read_byte(reader),
         {:ok, plug_id, reader} <- PacketReader.read_uint32(reader) do
      action =
        case action_byte do
          0 -> :install
          1 -> :remove
          2 -> :upgrade
          _ -> :install
        end

      {:ok,
       %__MODULE__{
         warplot_id: warplot_id,
         socket_id: socket_id,
         action: action,
         plug_id: if(action == :install and plug_id > 0, do: plug_id, else: nil)
       }, reader}
    end
  end
end
