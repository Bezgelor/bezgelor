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
      client_hello_auth: Handler.AuthHandler,
      client_encrypted: Handler.EncryptedHandler,
      client_hello_realm: Handler.RealmHandler
    }
  end
end
