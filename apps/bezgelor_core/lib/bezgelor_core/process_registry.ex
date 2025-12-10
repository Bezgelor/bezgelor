defmodule BezgelorCore.ProcessRegistry do
  @moduledoc """
  Process registry abstraction layer.

  Provides a unified interface for registering and looking up processes
  by type and ID. Currently backed by Elixir's Registry module.

  ## Process Types

  - `:zone_instance` - Zone instance processes
  - `:player` - Player session processes
  - `:creature` - Creature AI processes
  - `:guild` - Guild processes

  ## Usage

      # Register current process
      ProcessRegistry.register(:player, player_guid)
      ProcessRegistry.register(:player, player_guid, %{name: "Bob", level: 10})

      # Lookup
      case ProcessRegistry.lookup(:player, player_guid) do
        {:ok, pid} -> send(pid, :message)
        :error -> Logger.warning("Player not found")
      end

      # List all of a type
      for {id, pid} <- ProcessRegistry.list(:zone_instance) do
        send(pid, :shutdown)
      end

  ## Implementation Notes

  This module wraps Elixir's Registry to allow future migration to
  alternatives like :gproc if needed. The abstraction keeps the
  implementation detail hidden from consumers.
  """

  @registry_name __MODULE__.Registry

  @type process_type :: :zone_instance | :player | :creature | :guild | atom()
  @type process_id :: term()
  @type metadata :: map()

  @doc """
  Returns the child spec for the registry.

  Add to your application's supervision tree:

      children = [
        BezgelorCore.ProcessRegistry
      ]
  """
  def child_spec(_opts) do
    Registry.child_spec(keys: :unique, name: @registry_name)
  end

  @doc """
  Registers the current process with the given type and ID.

  Returns `{:ok, pid}` on success or `{:error, {:already_registered, pid}}`
  if another process is already registered with this key.

  ## Examples

      iex> ProcessRegistry.register(:player, 12345)
      {:ok, self()}

      iex> ProcessRegistry.register(:player, 12345, %{name: "Alice"})
      {:ok, self()}
  """
  @spec register(process_type(), process_id(), metadata()) ::
          {:ok, pid()} | {:error, {:already_registered, pid()}}
  def register(type, id, metadata \\ %{}) do
    case Registry.register(@registry_name, {type, id}, metadata) do
      {:ok, _} -> {:ok, self()}
      {:error, {:already_registered, pid}} -> {:error, {:already_registered, pid}}
    end
  end

  @doc """
  Looks up a process by type and ID.

  Returns `{:ok, pid}` if found, `:error` otherwise.

  ## Examples

      iex> ProcessRegistry.lookup(:player, 12345)
      {:ok, #PID<0.123.0>}

      iex> ProcessRegistry.lookup(:player, 99999)
      :error
  """
  @spec lookup(process_type(), process_id()) :: {:ok, pid()} | :error
  def lookup(type, id) do
    case Registry.lookup(@registry_name, {type, id}) do
      [{pid, _metadata}] -> {:ok, pid}
      [] -> :error
    end
  end

  @doc """
  Looks up a process and its metadata by type and ID.

  Returns `{:ok, pid, metadata}` if found, `:error` otherwise.

  ## Examples

      iex> ProcessRegistry.lookup_with_meta(:player, 12345)
      {:ok, #PID<0.123.0>, %{name: "Alice", level: 10}}
  """
  @spec lookup_with_meta(process_type(), process_id()) ::
          {:ok, pid(), metadata()} | :error
  def lookup_with_meta(type, id) do
    case Registry.lookup(@registry_name, {type, id}) do
      [{pid, metadata}] -> {:ok, pid, metadata}
      [] -> :error
    end
  end

  @doc """
  Returns the pid for a process, or nil if not found.

  Convenience function for pattern matching.

  ## Examples

      if pid = ProcessRegistry.whereis(:player, 12345) do
        send(pid, :message)
      end
  """
  @spec whereis(process_type(), process_id()) :: pid() | nil
  def whereis(type, id) do
    case lookup(type, id) do
      {:ok, pid} -> pid
      :error -> nil
    end
  end

  @doc """
  Lists all processes of a given type.

  Returns a list of `{id, pid}` tuples.

  ## Examples

      iex> ProcessRegistry.list(:zone_instance)
      [{"algoroc", #PID<0.100.0>}, {"whitevale", #PID<0.101.0>}]
  """
  @spec list(process_type()) :: [{process_id(), pid()}]
  def list(type) do
    match_pattern = {{type, :"$1"}, :"$2", :_}
    guards = []
    body = [{{:"$1", :"$2"}}]

    Registry.select(@registry_name, [{match_pattern, guards, body}])
  end

  @doc """
  Lists all processes of a given type with their metadata.

  Returns a list of `{id, pid, metadata}` tuples.

  ## Examples

      iex> ProcessRegistry.list_with_meta(:player)
      [{12345, #PID<0.100.0>, %{name: "Alice"}}, {12346, #PID<0.101.0>, %{name: "Bob"}}]
  """
  @spec list_with_meta(process_type()) :: [{process_id(), pid(), metadata()}]
  def list_with_meta(type) do
    match_pattern = {{type, :"$1"}, :"$2", :"$3"}
    guards = []
    body = [{{:"$1", :"$2", :"$3"}}]

    Registry.select(@registry_name, [{match_pattern, guards, body}])
  end

  @doc """
  Counts the number of registered processes of a given type.

  ## Examples

      iex> ProcessRegistry.count(:player)
      42
  """
  @spec count(process_type()) :: non_neg_integer()
  def count(type) do
    match_pattern = {{type, :_}, :_, :_}
    guards = []
    body = [true]

    Registry.select(@registry_name, [{match_pattern, guards, body}])
    |> length()
  end

  @doc """
  Unregisters a process by type and ID.

  Usually not needed as Registry automatically unregisters on process death.

  ## Examples

      iex> ProcessRegistry.unregister(:player, 12345)
      :ok
  """
  @spec unregister(process_type(), process_id()) :: :ok
  def unregister(type, id) do
    Registry.unregister(@registry_name, {type, id})
  end

  @doc """
  Updates the metadata for a registered process.

  The process must be registered from the calling process.

  ## Examples

      iex> ProcessRegistry.update_meta(:player, 12345, fn meta -> %{meta | level: 11} end)
      {:ok, %{name: "Alice", level: 11}}
  """
  @spec update_meta(process_type(), process_id(), (metadata() -> metadata())) ::
          {:ok, metadata()} | :error
  def update_meta(type, id, update_fn) do
    case Registry.update_value(@registry_name, {type, id}, update_fn) do
      {new_value, _old_value} -> {:ok, new_value}
      :error -> :error
    end
  end

  @doc """
  Sends a message to all processes of a given type.

  Returns the count of processes that received the message.

  ## Examples

      iex> ProcessRegistry.broadcast(:zone_instance, :tick)
      5
  """
  @spec broadcast(process_type(), term()) :: non_neg_integer()
  def broadcast(type, message) do
    processes = list(type)

    for {_id, pid} <- processes do
      send(pid, message)
    end

    length(processes)
  end
end
