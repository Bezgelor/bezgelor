defmodule BezgelorWorld.Event.Objectives do
  @moduledoc """
  Objective parsing and tracking logic for public events.

  This module contains pure functions for:
  - Validating objective types
  - Parsing objective definitions from event data
  - Checking objective completion status
  - Updating objective progress

  ## Objective Types

  Valid objective types are:
  - `:kill` - Kill a target creature or NPC
  - `:damage` - Deal damage to a target
  - `:collect` - Collect items
  - `:interact` - Interact with objects
  - `:territory` - Capture territory points
  - `:escort` - Escort NPCs
  - `:defend` - Defend a location
  - `:survive` - Survive for a duration
  - `:timer` - Complete within time limit

  ## Objective State

  Objectives are tracked as maps with:
  - `index` - Position in the objectives list
  - `type` - The objective type atom
  - `target` - Required progress amount
  - `target_id` - Optional specific target (e.g., creature_id)
  - `current` - Current progress
  """

  @type objective_state :: %{
          index: non_neg_integer(),
          type: atom(),
          target: non_neg_integer(),
          target_id: non_neg_integer() | nil,
          current: non_neg_integer()
        }

  # Valid objective types
  @valid_objective_types ~w(kill damage collect interact territory escort defend survive timer)a

  @doc """
  Returns the list of valid objective types.
  """
  @spec valid_objective_types() :: [atom()]
  def valid_objective_types, do: @valid_objective_types

  @doc """
  Safely convert an objective type to an atom.

  Returns a valid objective type atom, or :kill as a fallback.

  ## Examples

      iex> Objectives.safe_objective_type("kill")
      :kill

      iex> Objectives.safe_objective_type("invalid")
      :kill

      iex> Objectives.safe_objective_type(nil)
      :kill
  """
  @spec safe_objective_type(String.t() | atom() | nil) :: atom()
  def safe_objective_type(nil), do: :kill
  def safe_objective_type(type) when is_atom(type) and type in @valid_objective_types, do: type
  def safe_objective_type(type) when is_atom(type), do: :kill

  def safe_objective_type(type) when is_binary(type) do
    try do
      atom = String.to_existing_atom(type)
      if atom in @valid_objective_types, do: atom, else: :kill
    rescue
      ArgumentError -> :kill
    end
  end

  @doc """
  Parse objective definitions from event data.

  Converts a list of objective maps (from JSON) into objective state structs.

  ## Parameters

  - `objectives` - List of objective definition maps with "type", "target", "target_id" keys

  ## Returns

  List of objective state maps with parsed types and initial progress.
  """
  @spec parse_objectives([map()]) :: [objective_state()]
  def parse_objectives(objectives) do
    objectives
    |> Enum.with_index()
    |> Enum.map(fn {obj, index} ->
      %{
        index: index,
        type: safe_objective_type(obj["type"]),
        target: obj["target"] || 0,
        target_id: obj["target_id"],
        current: 0
      }
    end)
  end

  @doc """
  Check if all objectives have been met.

  An objective is met when its current progress >= target.

  ## Parameters

  - `objectives` - List of objective state maps

  ## Returns

  `true` if all objectives are complete, `false` otherwise.
  """
  @spec check_objectives_met([objective_state()]) :: boolean()
  def check_objectives_met(objectives) do
    Enum.all?(objectives, fn obj ->
      obj.current >= obj.target
    end)
  end

  @doc """
  Update objectives matching the given type and optional target_id.

  Increments progress on matching objectives that haven't reached their target.

  ## Parameters

  - `objectives` - List of objective state maps
  - `type` - The objective type to match
  - `target_id` - Optional target ID to match (nil matches all)
  - `amount` - Amount to increment progress (default 1)

  ## Returns

  Tuple of {updated_objectives, any_updated} where any_updated is true if
  any objective was actually updated.
  """
  @spec update_matching_objectives([objective_state()], atom(), non_neg_integer() | nil, non_neg_integer()) ::
          {[objective_state()], boolean()}
  def update_matching_objectives(objectives, type, target_id, amount \\ 1) do
    {updated_objectives, any_updated} =
      Enum.map_reduce(objectives, false, fn obj, updated ->
        if obj.type == type and (obj.target_id == nil or obj.target_id == target_id) and
             obj.current < obj.target do
          new_current = min(obj.current + amount, obj.target)
          {%{obj | current: new_current}, true}
        else
          {obj, updated}
        end
      end)

    {updated_objectives, any_updated}
  end

  @doc """
  Update territory-type objectives based on capture count.

  Sets the current value for all territory-type objectives to the given count.

  ## Parameters

  - `objectives` - List of objective state maps
  - `captured_count` - Number of territories captured

  ## Returns

  Updated list of objectives with territory objectives updated.
  """
  @spec update_territory_progress([objective_state()], non_neg_integer()) :: [objective_state()]
  def update_territory_progress(objectives, captured_count) do
    Enum.map(objectives, fn obj ->
      if obj.type == :territory do
        %{obj | current: captured_count}
      else
        obj
      end
    end)
  end

  @doc """
  Calculate progress percentage for an objective.

  ## Parameters

  - `objective` - An objective state map

  ## Returns

  Progress as a percentage (0-100).
  """
  @spec calculate_progress(objective_state()) :: non_neg_integer()
  def calculate_progress(%{target: 0}), do: 100
  def calculate_progress(%{current: current, target: target}) do
    min(100, div(current * 100, target))
  end

  @doc """
  Get a summary of objectives completion.

  ## Parameters

  - `objectives` - List of objective state maps

  ## Returns

  Map with completion statistics.
  """
  @spec objectives_summary([objective_state()]) :: map()
  def objectives_summary(objectives) do
    completed = Enum.count(objectives, fn obj -> obj.current >= obj.target end)
    total = length(objectives)

    %{
      completed: completed,
      total: total,
      all_complete: completed == total,
      progress_percent: if(total > 0, do: div(completed * 100, total), else: 100)
    }
  end
end
