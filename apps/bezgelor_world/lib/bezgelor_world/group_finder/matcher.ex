defmodule BezgelorWorld.GroupFinder.Matcher do
  @moduledoc """
  Matching algorithms for the group finder.

  Implements three tiers of matching:

  1. **Simple FIFO** - First-come, first-served for normal dungeons
  2. **Smart Matching** - Considers gear score, experience for veteran
  3. **Advanced Matching** - Complex composition rules for raids

  ## Role Requirements

  - **Dungeons/Adventures** (5 players): 1 tank, 1 healer, 3 DPS
  - **Raids** (20/40 players): 2-4 tanks, 4-6 healers, rest DPS
  - **Expeditions** (5 players): Flexible composition

  ## Matching Priority

  1. Players who have been waiting longest
  2. Role scarcity (tanks > healers > DPS)
  3. Instance preference alignment
  4. Gear score compatibility (smart matching)
  5. Language preference (raids)
  """

  require Logger

  @type role :: :tank | :healer | :dps
  @type match_result :: %{
          instance_id: non_neg_integer(),
          members: [%{character_id: non_neg_integer(), role: role()}]
        }

  @doc """
  Attempts to find a valid group from the queue.
  """
  @spec find_match(atom(), atom(), [map()]) :: {:ok, match_result()} | :no_match
  def find_match(instance_type, difficulty, queue) do
    case instance_type do
      :dungeon -> find_dungeon_match(difficulty, queue)
      :adventure -> find_dungeon_match(difficulty, queue)  # Same as dungeon
      :raid -> find_raid_match(difficulty, queue)
      :expedition -> find_expedition_match(difficulty, queue)
    end
  end

  @doc """
  Finds a match for 5-player content (dungeons, adventures).
  Requires: 1 tank, 1 healer, 3 DPS
  """
  @spec find_dungeon_match(atom(), [map()]) :: {:ok, match_result()} | :no_match
  def find_dungeon_match(difficulty, queue) do
    required = %{tank: 1, healer: 1, dps: 3}

    case difficulty do
      :normal -> find_fifo_match(queue, required)
      :veteran -> find_smart_match(queue, required)
      :challenge -> find_smart_match(queue, required)
      :mythic_plus -> find_smart_match(queue, required)
    end
  end

  @doc """
  Finds a match for raid content.
  Requires: 2+ tanks, 4+ healers, rest DPS
  """
  @spec find_raid_match(atom(), [map()]) :: {:ok, match_result()} | :no_match
  def find_raid_match(difficulty, queue) do
    # 20-player raid composition
    required = %{tank: 2, healer: 5, dps: 13}

    case difficulty do
      :normal -> find_fifo_match(queue, required)
      :veteran -> find_advanced_match(queue, required)
      _ -> find_advanced_match(queue, required)
    end
  end

  @doc """
  Finds a match for expeditions.
  Flexible composition - any 5 players.
  """
  @spec find_expedition_match(atom(), [map()]) :: {:ok, match_result()} | :no_match
  def find_expedition_match(_difficulty, queue) do
    if length(queue) >= 5 do
      # Take first 5 players, assign roles based on preference
      members =
        queue
        |> Enum.take(5)
        |> Enum.map(fn entry ->
          %{
            character_id: entry.character_id,
            role: hd(entry.roles)  # Use their primary role
          }
        end)

      instance_id = common_instance_preference(Enum.take(queue, 5))

      {:ok, %{instance_id: instance_id, members: members}}
    else
      :no_match
    end
  end

  # Simple FIFO matching - first-come, first-served
  defp find_fifo_match(queue, required) do
    # Sort by queue time (oldest first)
    sorted = Enum.sort_by(queue, & &1.queued_at)

    case fill_roles(sorted, required) do
      {:ok, members} ->
        instance_id = common_instance_preference(members)
        {:ok, %{instance_id: instance_id, members: format_members(members)}}

      :insufficient ->
        :no_match
    end
  end

  # Smart matching - considers gear score and wait time
  defp find_smart_match(queue, required) do
    # Score each player based on wait time and role scarcity
    scored =
      queue
      |> Enum.map(fn entry ->
        score = calculate_priority_score(entry, queue)
        {entry, score}
      end)
      |> Enum.sort_by(fn {_, score} -> -score end)
      |> Enum.map(fn {entry, _} -> entry end)

    case fill_roles_smart(scored, required) do
      {:ok, members} ->
        instance_id = common_instance_preference(members)
        {:ok, %{instance_id: instance_id, members: format_members(members)}}

      :insufficient ->
        :no_match
    end
  end

  # Advanced matching for raids - considers composition, language, etc.
  defp find_advanced_match(queue, required) do
    # Group by language preference first
    by_language = Enum.group_by(queue, & &1.language)

    # Try to form group from largest language group
    result =
      by_language
      |> Enum.sort_by(fn {_, players} -> -length(players) end)
      |> Enum.find_value(fn {_lang, players} ->
        case fill_roles_balanced(players, required) do
          {:ok, _} = success -> success
          :insufficient -> nil
        end
      end)

    case result do
      {:ok, members} ->
        instance_id = common_instance_preference(members)
        {:ok, %{instance_id: instance_id, members: format_members(members)}}

      nil ->
        # Fall back to mixed language if needed
        find_smart_match(queue, required)
    end
  end

  # Fill roles in FIFO order
  defp fill_roles(queue, required) do
    initial = %{tank: [], healer: [], dps: []}

    filled =
      Enum.reduce_while(queue, initial, fn entry, acc ->
        acc = try_assign_role(entry, acc, required)

        if roles_satisfied?(acc, required) do
          {:halt, acc}
        else
          {:cont, acc}
        end
      end)

    if roles_satisfied?(filled, required) do
      members = filled.tank ++ filled.healer ++ filled.dps
      {:ok, members}
    else
      :insufficient
    end
  end

  # Fill roles with smart prioritization
  defp fill_roles_smart(queue, required) do
    initial = %{tank: [], healer: [], dps: []}

    filled =
      Enum.reduce_while(queue, initial, fn entry, acc ->
        # Smart assignment - prefer scarce roles
        acc = try_assign_role_smart(entry, acc, required, queue)

        if roles_satisfied?(acc, required) do
          {:halt, acc}
        else
          {:cont, acc}
        end
      end)

    if roles_satisfied?(filled, required) do
      members = filled.tank ++ filled.healer ++ filled.dps
      {:ok, members}
    else
      :insufficient
    end
  end

  # Fill roles with balanced composition
  defp fill_roles_balanced(queue, required) do
    initial = %{tank: [], healer: [], dps: []}

    # Calculate gear score ranges for balance
    gear_scores = Enum.map(queue, & &1.gear_score)
    avg_gs = if length(gear_scores) > 0, do: Enum.sum(gear_scores) / length(gear_scores), else: 0
    gs_tolerance = 50  # Allow +/- 50 gear score variance

    # Prefer players close to average gear score
    sorted =
      queue
      |> Enum.sort_by(fn entry ->
        abs(entry.gear_score - avg_gs)
      end)

    filled =
      Enum.reduce_while(sorted, initial, fn entry, acc ->
        # Skip if too far from group average
        if abs(entry.gear_score - avg_gs) > gs_tolerance * 2 do
          {:cont, acc}
        else
          acc = try_assign_role(entry, acc, required)

          if roles_satisfied?(acc, required) do
            {:halt, acc}
          else
            {:cont, acc}
          end
        end
      end)

    if roles_satisfied?(filled, required) do
      members = filled.tank ++ filled.healer ++ filled.dps
      {:ok, members}
    else
      :insufficient
    end
  end

  defp try_assign_role(entry, filled, required) do
    cond do
      :tank in entry.roles and length(filled.tank) < required.tank ->
        %{filled | tank: [{entry, :tank} | filled.tank]}

      :healer in entry.roles and length(filled.healer) < required.healer ->
        %{filled | healer: [{entry, :healer} | filled.healer]}

      :dps in entry.roles and length(filled.dps) < required.dps ->
        %{filled | dps: [{entry, :dps} | filled.dps]}

      true ->
        filled
    end
  end

  defp try_assign_role_smart(entry, filled, required, queue) do
    # Calculate role scarcity
    tank_available = count_role_available(queue, :tank, filled.tank)
    healer_available = count_role_available(queue, :healer, filled.healer)
    dps_available = count_role_available(queue, :dps, filled.dps)

    tank_needed = required.tank - length(filled.tank)
    healer_needed = required.healer - length(filled.healer)
    dps_needed = required.dps - length(filled.dps)

    # Priority: fill scarce roles first
    roles_to_try =
      [{:tank, tank_needed, tank_available},
       {:healer, healer_needed, healer_available},
       {:dps, dps_needed, dps_available}]
      |> Enum.filter(fn {_role, needed, _} -> needed > 0 end)
      |> Enum.sort_by(fn {_role, needed, available} ->
        if available > 0, do: available / needed, else: 999
      end)
      |> Enum.map(fn {role, _, _} -> role end)

    # Try to assign to most needed role
    Enum.reduce_while(roles_to_try, filled, fn role, acc ->
      if role in entry.roles do
        case role do
          :tank -> {:halt, %{acc | tank: [{entry, :tank} | acc.tank]}}
          :healer -> {:halt, %{acc | healer: [{entry, :healer} | acc.healer]}}
          :dps -> {:halt, %{acc | dps: [{entry, :dps} | acc.dps]}}
        end
      else
        {:cont, acc}
      end
    end)
  end

  defp count_role_available(queue, role, already_assigned) do
    assigned_ids = MapSet.new(already_assigned, fn {entry, _} -> entry.character_id end)

    Enum.count(queue, fn entry ->
      role in entry.roles and not MapSet.member?(assigned_ids, entry.character_id)
    end)
  end

  defp roles_satisfied?(filled, required) do
    length(filled.tank) >= required.tank and
      length(filled.healer) >= required.healer and
      length(filled.dps) >= required.dps
  end

  defp format_members(members) do
    Enum.map(members, fn {entry, role} ->
      %{character_id: entry.character_id, role: role}
    end)
  end

  defp common_instance_preference(members) do
    # Find instance that most members have selected
    members
    |> Enum.flat_map(fn
      {entry, _role} -> entry.instance_ids
      entry -> entry.instance_ids
    end)
    |> Enum.frequencies()
    |> Enum.max_by(fn {_id, count} -> count end, fn -> {hd(members).instance_ids |> hd(), 1} end)
    |> elem(0)
  end

  defp calculate_priority_score(entry, queue) do
    # Base score from wait time (1 point per second)
    wait_seconds = div(System.monotonic_time(:millisecond) - entry.queued_at, 1000)

    # Bonus for scarce roles
    role_bonus =
      cond do
        :tank in entry.roles and count_role_in_queue(queue, :tank) < 3 -> 100
        :healer in entry.roles and count_role_in_queue(queue, :healer) < 3 -> 75
        true -> 0
      end

    wait_seconds + role_bonus
  end

  defp count_role_in_queue(queue, role) do
    Enum.count(queue, fn entry -> role in entry.roles end)
  end
end
