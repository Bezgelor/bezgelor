defmodule BezgelorProtocol.PacketRegistry do
  @moduledoc """
  Registry mapping opcodes to handler modules.

  ## Overview

  The PacketRegistry maintains a mapping from packet opcodes to handler
  modules. When a packet arrives, the Connection looks up the handler
  and dispatches the packet for processing.

  ## Built-in Handlers

  Some handlers are registered by default:

  - `:client_hello_auth` -> `BezgelorProtocol.Handler.AuthHandler`
  - `:client_encrypted` -> `BezgelorProtocol.Handler.EncryptedHandler`

  ## Custom Handlers

  You can register additional handlers at runtime:

      PacketRegistry.register(:my_opcode, MyHandler)

  Handler modules must implement the `BezgelorProtocol.Handler` behaviour.
  """

  use Agent

  alias BezgelorProtocol.Handler

  @doc "Start the packet registry."
  def start_link(_opts) do
    Agent.start_link(&init_handlers/0, name: __MODULE__)
  end

  @doc "Look up the handler for an opcode."
  @spec lookup(atom()) :: module() | nil
  def lookup(opcode) when is_atom(opcode) do
    case Process.whereis(__MODULE__) do
      nil ->
        # Registry not started, use default handlers
        Map.get(default_handlers(), opcode)

      _pid ->
        Agent.get(__MODULE__, &Map.get(&1, opcode))
    end
  end

  @doc "Register a handler for an opcode."
  @spec register(atom(), module()) :: :ok
  def register(opcode, handler) when is_atom(opcode) and is_atom(handler) do
    case Process.whereis(__MODULE__) do
      nil ->
        {:ok, _} = start_link([])
        register(opcode, handler)

      _pid ->
        Agent.update(__MODULE__, &Map.put(&1, opcode, handler))
    end
  end

  @doc "List all registered handlers."
  @spec all() :: %{atom() => module()}
  def all do
    case Process.whereis(__MODULE__) do
      nil -> default_handlers()
      _pid -> Agent.get(__MODULE__, & &1)
    end
  end

  # Private

  defp init_handlers do
    default_handlers()
  end

  defp default_handlers do
    %{
      # Connection state (ignored, sent by client during handshake)
      client_state: Handler.StateHandler,
      # STS Server handlers (port 6600)
      client_hello_auth: Handler.AuthHandler,
      client_encrypted: Handler.EncryptedHandler,
      # Realm Server handlers (port 23115)
      client_hello_auth_realm: Handler.RealmAuthHandler,
      # World Server handlers (port 24000) - protocol-layer only
      # World-layer handlers are registered at runtime by BezgelorWorld.HandlerRegistration
      client_hello_realm: Handler.WorldAuthHandler,
      client_packed_world: Handler.PackedWorldHandler,
      client_packed: Handler.PackedHandler,
      client_pregame_keep_alive: Handler.KeepAliveHandler,
      client_storefront_request_catalog: Handler.StorefrontRequestHandler,
      client_character_list: Handler.CharacterListHandler,
      client_character_create: Handler.CharacterCreateHandler,
      client_character_select: Handler.CharacterSelectHandler,
      client_character_delete: Handler.CharacterDeleteHandler,
      client_realm_list: Handler.RealmListHandler,
      client_realm_select: Handler.RealmSelectHandler,
      client_entered_world: Handler.WorldEntryHandler,
      client_logout_request: Handler.LogoutHandler,
      client_movement: Handler.MovementHandler,
      # Client statistics/telemetry
      client_statistics_connection: Handler.StatisticsConnectionHandler,
      client_statistics_framerate: Handler.StatisticsFramerateHandler,
      client_statistics_watchdog: Handler.StatisticsWatchdogHandler,
      client_statistics_window_open: Handler.StatisticsWindowOpenHandler,
      client_statistics_gfx: Handler.StatisticsGfxHandler,
      # Movement/Entity commands
      client_entity_command: Handler.EntityCommandHandler,
      client_zone_change: Handler.ZoneChangeHandler,
      client_player_movement_speed_update: Handler.MovementSpeedUpdateHandler,
      # Settings/Options
      client_options: Handler.OptionsHandler,
      # Keybindings
      client_request_input_key_set: Handler.InputKeySetHandler,
      # Entity targeting/selection
      client_entity_select: Handler.EntitySelectHandler,
      # Item/Inventory
      client_item_move: Handler.ItemMoveHandler,
      # Dialog acknowledgment
      client_dialog_opened: Handler.DialogOpenedHandler,
      # Marketplace/Auction
      client_request_owned_commodity_orders: Handler.CommodityOrdersHandler,
      client_request_owned_item_auctions: Handler.ItemAuctionsHandler,
      # Resurrection/Respawn
      client_resurrect_accept: Handler.ResurrectionHandler,
      client_resurrect_at_bindpoint: Handler.ResurrectionHandler,
      # Unknown opcodes (for investigation)
      client_unknown_0x0269: Handler.Unknown0x0269Handler,
      client_unknown_0x07CC: Handler.Unknown0x07CCHandler,
      client_unknown_0x00D5: Handler.Unknown0x00D5Handler,
      client_unknown_0x00DE: Handler.Unknown0x00DEHandler,
      client_unknown_0x00FB: Handler.Unknown0x00FBHandler,
      client_unknown_0x0635: Handler.Unknown0x0635Handler,
      client_unknown_0x00E3: Handler.Unknown0x00E3Handler,
      client_p2p_trading_cancel: Handler.P2PTradingCancelHandler
    }
  end
end
