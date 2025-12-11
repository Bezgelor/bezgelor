defmodule BezgelorWorld.WorldManager do
  @moduledoc """
  Manages active world sessions and entity state.

  ## Overview

  The WorldManager is responsible for:
  - Generating unique entity GUIDs
  - Tracking active player sessions
  - Managing entity registry
  - Coordinating visibility updates (future)

  For Phase 6, this is a simple registry. Future phases will add
  zones, visibility ranges, and multi-server coordination.

  ## Entity GUIDs

  GUIDs are 64-bit identifiers structured as:
  - Bits 60-63: Entity type (1=player, 2=creature, 3=object, 4=vehicle)
  - Bits 48-59: Reserved for server ID
  - Bits 0-47: Unique counter

  ## Session Tracking

  Each connected player has a session entry tracking:
  - Account ID
  - Character ID
  - Connection PID
  - Entity GUID
  """

  use GenServer

  import Bitwise

  require Logger

  @type session :: %{
          character_id: non_neg_integer(),
          character_name: String.t() | nil,
          connection_pid: pid(),
          entity_guid: non_neg_integer() | nil
        }

  @type state :: %{
          sessions: %{non_neg_integer() => session()},
          entities: %{non_neg_integer() => any()},
          next_guid_counter: non_neg_integer()
        }

  # Entity type bits
  @entity_type_player 1
  @entity_type_creature 2
  @entity_type_object 3
  @entity_type_vehicle 4

  ## Client API

  @doc "Start the WorldManager."
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Generate a unique entity GUID."
  @spec generate_guid(atom()) :: non_neg_integer()
  def generate_guid(entity_type \\ :player) do
    GenServer.call(__MODULE__, {:generate_guid, entity_type})
  end

  @doc "Register a player session."
  @spec register_session(non_neg_integer(), non_neg_integer(), String.t() | nil, pid()) :: :ok
  def register_session(account_id, character_id, character_name, connection_pid) do
    GenServer.call(__MODULE__, {:register_session, account_id, character_id, character_name, connection_pid})
  end

  @doc "Update session with entity GUID."
  @spec set_entity_guid(non_neg_integer(), non_neg_integer()) :: :ok
  def set_entity_guid(account_id, entity_guid) do
    GenServer.cast(__MODULE__, {:set_entity_guid, account_id, entity_guid})
  end

  @doc "Unregister a player session."
  @spec unregister_session(non_neg_integer()) :: :ok
  def unregister_session(account_id) do
    GenServer.cast(__MODULE__, {:unregister_session, account_id})
  end

  @doc "Get session info for an account."
  @spec get_session(non_neg_integer()) :: session() | nil
  def get_session(account_id) do
    GenServer.call(__MODULE__, {:get_session, account_id})
  end

  @doc "Get all active sessions."
  @spec list_sessions() :: %{non_neg_integer() => session()}
  def list_sessions do
    GenServer.call(__MODULE__, :list_sessions)
  end

  @doc "Get session count."
  @spec session_count() :: non_neg_integer()
  def session_count do
    GenServer.call(__MODULE__, :session_count)
  end

  @doc "Broadcast chat to nearby players."
  @spec broadcast_chat(non_neg_integer(), String.t(), atom(), String.t(), {float(), float(), float()}) :: :ok
  def broadcast_chat(sender_guid, sender_name, channel, message, position) do
    GenServer.cast(__MODULE__, {:broadcast_chat, sender_guid, sender_name, channel, message, position})
  end

  @doc "Send whisper to a specific player by name."
  @spec send_whisper(non_neg_integer(), String.t(), String.t(), String.t()) ::
          :ok | {:error, :player_not_found | :player_offline}
  def send_whisper(sender_guid, sender_name, target_name, message) do
    GenServer.call(__MODULE__, {:send_whisper, sender_guid, sender_name, target_name, message})
  end

  @doc "Find session by character name."
  @spec find_session_by_name(String.t()) :: {non_neg_integer(), session()} | nil
  def find_session_by_name(character_name) do
    GenServer.call(__MODULE__, {:find_session_by_name, character_name})
  end

  @doc "Get session info by character ID."
  @spec get_session_by_character(non_neg_integer()) :: session() | nil
  def get_session_by_character(character_id) do
    GenServer.call(__MODULE__, {:get_session_by_character, character_id})
  end

  @doc "Send a packet to a specific connection process."
  @spec send_packet(pid(), atom(), binary()) :: :ok
  def send_packet(connection_pid, opcode, packet_data) do
    send(connection_pid, {:send_packet, opcode, packet_data})
    :ok
  end

  ## Server Callbacks

  @impl true
  def init(_opts) do
    state = %{
      sessions: %{},
      entities: %{},
      next_guid_counter: 1
    }

    Logger.info("WorldManager started")
    {:ok, state}
  end

  @impl true
  def handle_call({:generate_guid, entity_type}, _from, state) do
    type_bits = entity_type_to_bits(entity_type)
    counter = state.next_guid_counter

    # Format: [type:4][reserved:12][counter:48]
    guid = bsl(type_bits, 60) ||| (counter &&& 0xFFFFFFFFFFFF)

    {:reply, guid, %{state | next_guid_counter: counter + 1}}
  end

  @impl true
  def handle_call({:register_session, account_id, character_id, character_name, connection_pid}, _from, state) do
    session = %{
      character_id: character_id,
      character_name: character_name,
      connection_pid: connection_pid,
      entity_guid: nil
    }

    sessions = Map.put(state.sessions, account_id, session)

    Logger.debug("Registered session for account #{account_id}, character #{character_name}")
    {:reply, :ok, %{state | sessions: sessions}}
  end

  @impl true
  def handle_call({:get_session, account_id}, _from, state) do
    session = Map.get(state.sessions, account_id)
    {:reply, session, state}
  end

  @impl true
  def handle_call(:list_sessions, _from, state) do
    {:reply, state.sessions, state}
  end

  @impl true
  def handle_call(:session_count, _from, state) do
    {:reply, map_size(state.sessions), state}
  end

  @impl true
  def handle_call({:find_session_by_name, character_name}, _from, state) do
    result =
      Enum.find(state.sessions, fn {_account_id, session} ->
        session.character_name != nil and
          String.downcase(session.character_name) == String.downcase(character_name)
      end)

    {:reply, result, state}
  end

  @impl true
  def handle_call({:get_session_by_character, character_id}, _from, state) do
    result =
      state.sessions
      |> Enum.find(fn {_account_id, session} -> session.character_id == character_id end)
      |> case do
        {_account_id, session} -> session
        nil -> nil
      end

    {:reply, result, state}
  end

  @impl true
  def handle_call({:send_whisper, sender_guid, sender_name, target_name, message}, _from, state) do
    result =
      case find_session_by_name_in_state(state.sessions, target_name) do
        nil ->
          {:error, :player_not_found}

        {_account_id, session} ->
          # Send the whisper to target's connection
          send_chat_to_connection(
            session.connection_pid,
            sender_guid,
            sender_name,
            :whisper,
            message
          )

          :ok
      end

    {:reply, result, state}
  end

  @impl true
  def handle_cast({:set_entity_guid, account_id, entity_guid}, state) do
    state =
      case Map.get(state.sessions, account_id) do
        nil ->
          state

        session ->
          session = %{session | entity_guid: entity_guid}
          sessions = Map.put(state.sessions, account_id, session)
          %{state | sessions: sessions}
      end

    {:noreply, state}
  end

  @impl true
  def handle_cast({:unregister_session, account_id}, state) do
    sessions = Map.delete(state.sessions, account_id)
    Logger.debug("Unregistered session for account #{account_id}")
    {:noreply, %{state | sessions: sessions}}
  end

  @impl true
  def handle_cast({:broadcast_chat, sender_guid, sender_name, channel, message, _position}, state) do
    # For now, broadcast to all sessions (zone/range filtering is future work)
    # In a full implementation, we would filter by position/range
    Enum.each(state.sessions, fn {_account_id, session} ->
      # Don't send to sender (they already got the echo in ChatHandler)
      if session.entity_guid != sender_guid do
        send_chat_to_connection(
          session.connection_pid,
          sender_guid,
          sender_name,
          channel,
          message
        )
      end
    end)

    {:noreply, state}
  end

  # Private

  defp entity_type_to_bits(:player), do: @entity_type_player
  defp entity_type_to_bits(:creature), do: @entity_type_creature
  defp entity_type_to_bits(:object), do: @entity_type_object
  defp entity_type_to_bits(:vehicle), do: @entity_type_vehicle
  defp entity_type_to_bits(_), do: @entity_type_object

  defp find_session_by_name_in_state(sessions, character_name) do
    Enum.find(sessions, fn {_account_id, session} ->
      session.character_name != nil and
        String.downcase(session.character_name) == String.downcase(character_name)
    end)
  end

  defp send_chat_to_connection(connection_pid, sender_guid, sender_name, channel, message) do
    # Send chat message to a connection process
    # The connection process should handle :send_chat message
    send(connection_pid, {:send_chat, sender_guid, sender_name, channel, message})
  end
end
