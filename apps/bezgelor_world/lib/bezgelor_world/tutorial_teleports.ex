defmodule BezgelorWorld.TutorialTeleports do
  @moduledoc """
  Tutorial zone teleport pad configuration.

  Maps trigger world locations to teleport destinations with optional quest gates.
  When a player enters a trigger volume and meets the quest requirements, they
  are teleported to the destination.

  ## Configuration Format

      %{
        trigger_id: world_location_id that triggers the teleport,
        destination_id: world_location_id to teleport to,
        quest_gate: quest_id that must be completable (optional),
        auto_complete_quest: true to auto-complete the gate quest
      }

  ## Usage

      case TutorialTeleports.check_teleport(session_data, trigger_id) do
        {:teleport, destination_id, opts} ->
          # Execute teleport
        :no_teleport ->
          # No teleport for this trigger
      end
  """

  alias BezgelorWorld.Teleport

  require Logger

  @type teleport_config :: %{
          trigger_id: non_neg_integer(),
          destination_id: non_neg_integer(),
          quest_gate: non_neg_integer() | nil,
          auto_complete_quest: boolean()
        }

  # ============================================================================
  # Tutorial Teleport Configurations
  # ============================================================================

  # Exile tutorial teleport pads
  @exile_teleports [
    # Cryo bay to main deck (after intro objectives)
    # %{
    #   trigger_id: 50231,  # World location ID of teleport pad
    #   destination_id: 50232,  # Destination world location
    #   quest_gate: 8042,  # Quest that must be completable
    #   auto_complete_quest: true
    # }
  ]

  # Dominion tutorial teleport pads
  @dominion_teleports [
    # Similar structure for Dominion tutorial
  ]

  # All tutorial teleports combined
  @all_teleports @exile_teleports ++ @dominion_teleports

  # Build lookup map at compile time
  @teleport_by_trigger Map.new(@all_teleports, fn config ->
                         {config.trigger_id, config}
                       end)

  # ============================================================================
  # Public API
  # ============================================================================

  @doc """
  Check if a trigger should teleport the player.

  Returns `{:teleport, destination_id, opts}` if conditions are met,
  or `:no_teleport` if the trigger doesn't cause a teleport or conditions aren't met.
  """
  @spec check_teleport(map(), non_neg_integer()) ::
          {:teleport, non_neg_integer(), keyword()} | :no_teleport
  def check_teleport(session_data, trigger_id) do
    case Map.get(@teleport_by_trigger, trigger_id) do
      nil ->
        :no_teleport

      config ->
        check_teleport_conditions(session_data, config)
    end
  end

  @doc """
  Execute a tutorial teleport if conditions are met.

  This is called from MovementHandler when a trigger is entered.
  Returns updated session_data and any packets to send.
  """
  @spec maybe_teleport(map(), non_neg_integer()) :: {map(), [{atom(), binary()}]}
  def maybe_teleport(session_data, trigger_id) do
    case check_teleport(session_data, trigger_id) do
      {:teleport, destination_id, opts} ->
        execute_teleport(session_data, destination_id, opts)

      :no_teleport ->
        {session_data, []}
    end
  end

  # ============================================================================
  # Private Implementation
  # ============================================================================

  defp check_teleport_conditions(session_data, config) do
    quest_gate = config.quest_gate

    cond do
      # No quest gate - always teleport
      is_nil(quest_gate) ->
        {:teleport, config.destination_id, [auto_complete: config.auto_complete_quest, quest_id: nil]}

      # Check if quest is completable (all objectives done)
      quest_completable?(session_data, quest_gate) ->
        {:teleport, config.destination_id,
         [auto_complete: config.auto_complete_quest, quest_id: quest_gate]}

      # Quest not ready
      true ->
        :no_teleport
    end
  end

  defp quest_completable?(session_data, quest_id) do
    active_quests = session_data[:active_quests] || %{}

    case Map.get(active_quests, quest_id) do
      nil ->
        false

      quest ->
        quest.state == :complete or all_objectives_complete?(quest)
    end
  end

  defp all_objectives_complete?(quest) do
    Enum.all?(quest.objectives, fn obj ->
      obj.current >= obj.target
    end)
  end

  defp execute_teleport(session_data, destination_id, opts) do
    quest_id = opts[:quest_id]
    auto_complete = opts[:auto_complete] || false

    Logger.info(
      "Tutorial teleport triggered: destination=#{destination_id}, quest=#{inspect(quest_id)}, auto_complete=#{auto_complete}"
    )

    # Auto-complete quest if configured
    session_data =
      if auto_complete and quest_id do
        auto_complete_quest(session_data, quest_id)
      else
        session_data
      end

    # Execute teleport - returns {:ok, session} or {:error, reason}
    case Teleport.to_world_location(session_data, destination_id) do
      {:ok, updated_session} ->
        # Teleport successful - packets handled internally by Teleport module
        {updated_session, []}

      {:error, reason} ->
        Logger.warning("Tutorial teleport failed: #{inspect(reason)}")
        {session_data, []}
    end
  end

  defp auto_complete_quest(session_data, quest_id) do
    active_quests = session_data[:active_quests] || %{}
    completed_ids = session_data[:completed_quest_ids] || MapSet.new()

    case Map.get(active_quests, quest_id) do
      nil ->
        session_data

      _quest ->
        # Move from active to completed
        remaining_quests = Map.delete(active_quests, quest_id)
        updated_completed = MapSet.put(completed_ids, quest_id)

        Logger.info("Auto-completed quest #{quest_id}")

        session_data
        |> Map.put(:active_quests, remaining_quests)
        |> Map.put(:completed_quest_ids, updated_completed)
    end
  end

  # ============================================================================
  # Configuration Helpers
  # ============================================================================

  @doc """
  Get all configured tutorial teleport triggers.

  Useful for debugging and inspection.
  """
  @spec get_all_teleports() :: [teleport_config()]
  def get_all_teleports, do: @all_teleports

  @doc """
  Check if a trigger ID is a tutorial teleport trigger.
  """
  @spec is_teleport_trigger?(non_neg_integer()) :: boolean()
  def is_teleport_trigger?(trigger_id) do
    Map.has_key?(@teleport_by_trigger, trigger_id)
  end
end
