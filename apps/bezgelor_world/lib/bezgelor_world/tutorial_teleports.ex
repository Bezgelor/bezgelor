defmodule BezgelorWorld.TutorialTeleports do
  @moduledoc """
  Tutorial quest teleport reward configuration.

  Maps quests to teleport destinations that execute when the quest becomes
  completable. This avoids burdening the movement handler with tutorial
  checks that only apply for the first 15 minutes of gameplay.

  ## Configuration Format

      %{
        quest_id: quest that triggers teleport on completion,
        destination_id: world_location_id to teleport to
      }

  ## Usage

  Called from SessionQuestManager when a quest becomes completable:

      case TutorialTeleports.get_teleport_for_quest(quest_id) do
        {:ok, destination_id} ->
          Teleport.to_world_location(session, destination_id)
        :none ->
          # No teleport for this quest
      end
  """

  alias BezgelorWorld.Teleport

  require Logger

  @type teleport_config :: %{
          quest_id: non_neg_integer(),
          destination_id: non_neg_integer()
        }

  # ============================================================================
  # Tutorial Quest Teleport Configurations
  # ============================================================================

  # Quests that teleport the player on completion
  # Add tutorial quest IDs here when known from game data
  @quest_teleports [
    # Example: Cryo bay exit quest teleports to main deck
    # %{quest_id: 8042, destination_id: 50232}
  ]

  # Build lookup map at compile time
  @teleport_by_quest Map.new(@quest_teleports, fn config ->
                       {config.quest_id, config.destination_id}
                     end)

  # ============================================================================
  # Public API
  # ============================================================================

  @doc """
  Get the teleport destination for a quest, if configured.

  Returns `{:ok, destination_id}` if the quest has a teleport reward,
  or `:none` if no teleport is configured.
  """
  @spec get_teleport_for_quest(non_neg_integer()) :: {:ok, non_neg_integer()} | :none
  def get_teleport_for_quest(quest_id) do
    case Map.get(@teleport_by_quest, quest_id) do
      nil -> :none
      destination_id -> {:ok, destination_id}
    end
  end

  @doc """
  Execute a teleport reward for a quest that just became completable.

  Returns `{:ok, updated_session}` or `{:error, reason}`.
  """
  @spec execute_quest_teleport(map(), non_neg_integer()) ::
          {:ok, map()} | {:error, atom()} | :no_teleport
  def execute_quest_teleport(session_data, quest_id) do
    case get_teleport_for_quest(quest_id) do
      {:ok, destination_id} ->
        Logger.info("Quest #{quest_id} completed - teleporting to #{destination_id}")
        Teleport.to_world_location(session_data, destination_id)

      :none ->
        :no_teleport
    end
  end

  @doc """
  Check if a quest has a teleport reward configured.
  """
  @spec has_teleport_reward?(non_neg_integer()) :: boolean()
  def has_teleport_reward?(quest_id) do
    Map.has_key?(@teleport_by_quest, quest_id)
  end

  @doc """
  Get all configured quest teleports.

  Useful for debugging and inspection.
  """
  @spec get_all_teleports() :: [teleport_config()]
  def get_all_teleports, do: @quest_teleports
end
