defmodule BezgelorProtocol.Packets.World.ServerActionSet do
  @moduledoc """
  ServerActionSet packet (0x019D).

  Configures the player's action bar (Limited Action Set) for a spec.
  Each action set can hold up to 48 action slots.
  """

  alias BezgelorProtocol.PacketWriter

  @behaviour BezgelorProtocol.Packet.Writable

  # LimitedActionSetResult enum values
  @result_ok 0

  # ShortcutType enum values
  @shortcut_none 0
  @shortcut_bag_item 1
  @shortcut_macro 2
  @shortcut_game_command 3
  @shortcut_spellbook_item 4

  # InventoryLocation values
  @inventory_ability 4
  @inventory_empty 300

  # Maximum action slots in a Limited Action Set
  @max_action_count 48

  defstruct spec_index: 0,
            unlocked: true,
            result: :ok,
            actions: []

  @type shortcut_type :: :none | :bag_item | :macro | :game_command | :spell
  @type result :: :ok

  @type action :: %{
          type: shortcut_type(),
          object_id: non_neg_integer(),
          slot: non_neg_integer()
        }

  @type t :: %__MODULE__{
          spec_index: non_neg_integer(),
          unlocked: boolean(),
          result: result(),
          actions: [action()]
        }

  @impl true
  def opcode, do: :server_action_set

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    # Build full action list (fill empty slots up to 48)
    actions = build_full_action_list(packet.actions)

    writer =
      writer
      |> PacketWriter.write_bits(packet.spec_index, 3)
      |> PacketWriter.write_bits(if(packet.unlocked, do: 1, else: 0), 2)
      |> PacketWriter.write_bits(result_to_int(packet.result), 6)
      |> PacketWriter.write_bits(length(actions), 6)

    # Write each action
    writer = Enum.reduce(actions, writer, &write_action/2)

    writer = PacketWriter.flush_bits(writer)
    {:ok, writer}
  end

  # Build a full 48-slot action list, filling empty slots
  defp build_full_action_list(provided_actions) do
    # Create a map of slot -> action
    action_map =
      provided_actions
      |> Enum.map(fn action -> {action.slot, action} end)
      |> Map.new()

    # Generate all 48 slots
    for slot <- 0..(@max_action_count - 1) do
      case Map.get(action_map, slot) do
        nil -> %{type: :none, object_id: 0, slot: slot}
        action -> action
      end
    end
  end

  defp write_action(action, writer) do
    shortcut_type = type_to_int(action.type)
    object_id = Map.get(action, :object_id, 0)
    bag_index = Map.get(action, :ui_location, action.slot)

    location =
      case action.type do
        :spell -> @inventory_ability
        :none -> @inventory_empty
        _ -> @inventory_empty
      end

    writer
    |> PacketWriter.write_bits(shortcut_type, 4)
    |> PacketWriter.write_bits(location, 9)
    |> PacketWriter.write_u32(bag_index)
    |> PacketWriter.write_u32(object_id)
  end

  defp result_to_int(:ok), do: @result_ok
  defp result_to_int(_), do: @result_ok

  defp type_to_int(:none), do: @shortcut_none
  defp type_to_int(:bag_item), do: @shortcut_bag_item
  defp type_to_int(:macro), do: @shortcut_macro
  defp type_to_int(:game_command), do: @shortcut_game_command
  defp type_to_int(:spell), do: @shortcut_spellbook_item
end
