defmodule BezgelorWorld.Encounter.Generator do
  @moduledoc """
  Generates Elixir DSL boss encounter modules from JSON encounter data.

  This module transforms structured encounter data (from client extraction,
  community research, or LLM generation) into compilable Elixir modules
  using the BezgelorWorld.Encounter.DSL macro system.
  """

  # Whitelists for safe atom conversion - prevents atom table exhaustion
  # from malicious or corrupted JSON encounter data

  @valid_shapes ~w(circle cone line donut cross room_wide)a
  @valid_colors ~w(red orange yellow blue green purple white gray)a
  @valid_damage_types ~w(magic physical fire frost nature shadow holy)a
  @valid_movement_types ~w(knockback pull charge dash leap teleport)a
  @valid_spawn_types ~w(add minion elite boss)a
  @valid_coordination_types ~w(stack spread soak chain)a

  # Safe atom conversion with whitelist validation
  defp safe_to_atom(value, whitelist, default) when is_binary(value) do
    atom = String.to_existing_atom(value)
    if atom in whitelist, do: atom, else: default
  rescue
    ArgumentError -> default
  end

  defp safe_to_atom(value, whitelist, default) when is_atom(value) do
    if value in whitelist, do: value, else: default
  end

  defp safe_to_atom(_value, _whitelist, default), do: default

  @doc """
  Generate a complete boss module from boss data and encounter context.
  """
  def generate_boss_module(boss, encounter_data) do
    boss_name = boss["name"] || "Unknown"
    difficulty = boss["difficulty"] || "normal"
    boss_module_name = boss_to_module_name(boss_name, difficulty)
    instance_name = encounter_data["instance_name"] || "Unknown Instance"
    instance_module_name = instance_to_module_name(instance_name)

    # Full module path includes instance namespace
    full_module_name = "#{instance_module_name}.#{boss_module_name}"

    # Extract data completeness for documentation
    completeness = boss["data_completeness"] || 0.0
    sources = boss["data_sources"] || []

    # Get ability research if available
    ability_research = encounter_data["ability_research"] || %{}

    """
    defmodule BezgelorWorld.Encounter.Bosses.#{full_module_name} do
      @moduledoc \"\"\"
      #{boss_name} encounter - #{instance_name}

      Data sources: #{format_sources(sources)}
      Data completeness: #{round(completeness * 100)}%
      Generated: #{Date.to_string(Date.utc_today())}

      #{generate_ability_notes(boss, ability_research)}
      \"\"\"

      use BezgelorWorld.Encounter.DSL

      boss "#{boss_name}" do
    #{generate_boss_attributes(boss)}

    #{generate_phases(boss)}

        on_death do
          loot_table #{boss["boss_id"] || 0}
        end
      end
    end
    """
    |> format_code()
  end

  @doc """
  Convert a boss name and difficulty to a valid Elixir module name.
  """
  def boss_to_module_name(name, difficulty \\ "normal") do
    base =
      name
      |> String.replace(~r/[^a-zA-Z0-9\s]/, "")
      |> String.split()
      |> Enum.map(&String.capitalize/1)
      |> Enum.join("")

    case difficulty do
      "normal" -> base
      "prime" -> "#{base}Prime"
      "veteran" -> "#{base}Veteran"
      other -> "#{base}#{String.capitalize(other)}"
    end
  end

  @doc """
  Convert a module name to a snake_case filename.
  """
  def module_to_filename(module_name) do
    module_name
    |> Macro.underscore()
    |> Kernel.<>(".ex")
  end

  @doc """
  Convert an instance name to a directory name.
  """
  def instance_to_dirname(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9\s]/, "")
    |> String.replace(~r/\s+/, "_")
  end

  @doc """
  Convert an instance name to a valid Elixir module name.
  """
  def instance_to_module_name(name) do
    name
    |> String.replace(~r/[^a-zA-Z0-9\s]/, "")
    |> String.split()
    |> Enum.map(&String.capitalize/1)
    |> Enum.join("")
  end

  # Private functions

  defp format_sources([]), do: "unknown"
  defp format_sources(sources), do: Enum.join(sources, ", ")

  defp generate_ability_notes(boss, ability_research) do
    ability_names = ability_research["ability_names_found"] || []
    spell_bases = ability_research["spell_bases_found"] || %{}

    # Find abilities that might belong to this boss
    _boss_name = boss["name"] || ""

    relevant_notes =
      ability_names
      |> Enum.filter(fn name ->
        # Include abilities that might be for this boss
        # This is a heuristic - abilities are listed globally
        spell_ids = Map.get(spell_bases, name, [])
        length(spell_ids) > 0
      end)
      |> Enum.map(fn name ->
        spell_ids = Map.get(spell_bases, name, [])
        "  - #{name}: spell_base_ids #{inspect(spell_ids)}"
      end)

    if Enum.empty?(relevant_notes) do
      "No ability data found in client extraction."
    else
      "Known abilities from client data:\n#{Enum.join(relevant_notes, "\n")}"
    end
  end

  defp generate_boss_attributes(boss) do
    boss_id = boss["boss_id"] || boss["creature_id"] || 0
    level = boss["level"] || 20
    health = estimate_health(level, boss["difficulty"])
    interrupt_armor = boss["interrupt_armor"] || 2
    enrage_timer = boss["enrage_timer"] || 480_000

    """
        boss_id #{boss_id}
        health #{format_number(health)}
        level #{level}
        enrage_timer #{enrage_timer}
        interrupt_armor #{interrupt_armor}
    """
    |> String.trim_trailing()
  end

  defp estimate_health(level, difficulty) do
    base_health =
      cond do
        level <= 20 -> 400_000
        level <= 35 -> 1_500_000
        level <= 50 -> 5_000_000
        true -> 10_000_000
      end

    multiplier =
      case difficulty do
        "prime" -> 3.0
        "veteran" -> 1.5
        _ -> 1.0
      end

    round(base_health * multiplier)
  end

  defp generate_phases(boss) do
    phases = boss["phases"] || []

    if Enum.empty?(phases) do
      # Generate default phases if none specified
      generate_default_phases(boss)
    else
      phases
      |> Enum.map(&generate_phase/1)
      |> Enum.join("\n\n")
    end
  end

  defp generate_default_phases(boss) do
    level = boss["level"] || 20
    abilities = boss["abilities"] || []

    if Enum.empty?(abilities) do
      # Generate placeholder phases with TODO comments
      """
          # TODO: Add phases and abilities based on research
          # Use the LLM scripting guide: docs/llm-scripting-guide.md

          phase :one, health_above: 70 do
            phase_emote "#{boss["name"] || "The boss"} engages!"

            # TODO: Add abilities
            ability :basic_attack, cooldown: 10_000, target: :tank do
              telegraph :circle, radius: 5, duration: 2000, color: :red
              damage #{estimate_damage(level, :medium)}, type: :physical
            end
          end

          phase :two, health_between: {30, 70} do
            inherit_phase :one

            # TODO: Add phase two abilities
          end

          phase :three, health_below: 30 do
            inherit_phase :two
            enrage_modifier 1.5

            # TODO: Add enrage abilities
          end
      """
    else
      # Generate phases from abilities
      generate_phases_from_abilities(boss, abilities)
    end
  end

  defp generate_phases_from_abilities(boss, abilities) do
    level = boss["level"] || 20

    """
        phase :one, health_above: 70 do
          phase_emote "#{boss["name"] || "The boss"} engages!"

    #{generate_abilities(abilities, level)}
        end

        phase :two, health_between: {30, 70} do
          inherit_phase :one
          phase_emote "#{boss["name"] || "The boss"} grows stronger!"
        end

        phase :three, health_below: 30 do
          inherit_phase :two
          enrage_modifier 1.5
          phase_emote "#{boss["name"] || "The boss"} enters a frenzy!"
        end
    """
  end

  defp generate_phase(phase) do
    name = phase["name"] || "unnamed"
    condition = generate_phase_condition(phase["condition"])
    emote = phase["emote"] || phase["phase_emote"]
    abilities = phase["abilities"] || []
    inherit = phase["inherit_phase"]
    enrage_mod = phase["enrage_modifier"]

    ability_code =
      if Enum.empty?(abilities) do
        "      # TODO: Add abilities for this phase"
      else
        generate_abilities(abilities, phase["level"] || 20)
      end

    """
        phase :#{name}, #{condition} do
    #{if emote, do: "      phase_emote \"#{emote}\"\n", else: ""}#{if inherit, do: "      inherit_phase :#{inherit}\n", else: ""}#{if enrage_mod, do: "      enrage_modifier #{enrage_mod}\n", else: ""}
    #{ability_code}
        end
    """
    |> String.trim_trailing()
  end

  defp generate_phase_condition(nil), do: "health_above: 100"
  defp generate_phase_condition(%{"health_above" => value}), do: "health_above: #{value}"
  defp generate_phase_condition(%{"health_below" => value}), do: "health_below: #{value}"

  defp generate_phase_condition(%{"health_between" => [min, max]}),
    do: "health_between: {#{min}, #{max}}"

  defp generate_phase_condition(%{"always" => true}), do: "always: true"
  defp generate_phase_condition(_), do: "health_above: 100"

  defp generate_abilities(abilities, level) do
    abilities
    |> Enum.map(fn ability -> generate_ability(ability, level) end)
    |> Enum.join("\n\n")
  end

  defp generate_ability(ability, level) do
    name = ability_to_atom_name(ability["name"] || "unnamed")
    cooldown = ability["cooldown"] || 15_000
    target = ability["target"] || "random"

    effects = ability["effects"] || []

    effect_code =
      if Enum.empty?(effects) do
        generate_default_effects(ability, level)
      else
        effects
        |> Enum.map(fn effect -> generate_effect(effect, level) end)
        |> Enum.join("\n")
      end

    """
          ability :#{name}, cooldown: #{cooldown}, target: :#{target} do
    #{effect_code}
          end
    """
    |> String.trim_trailing()
  end

  defp generate_default_effects(ability, level) do
    type = ability["type"] || "telegraph"
    damage_type = ability["damage_type"] || "magic"

    case type do
      "telegraph" ->
        shape = ability["telegraph_shape"] || "circle"
        radius = ability["radius"] || 5

        """
                telegraph :#{shape}, radius: #{radius}, duration: 2000, color: :red
                damage #{estimate_damage(level, :medium)}, type: :#{damage_type}
        """

      "spawn" ->
        creature_id = ability["creature_id"] || 0
        count = ability["count"] || 1

        """
                spawn :add, creature_id: #{creature_id}, count: #{count}
        """

      "buff" ->
        buff_name = ability["buff_name"] || "enrage"
        duration = ability["duration"] || 10_000

        """
                buff :#{buff_name}, duration: #{duration}
        """

      "debuff" ->
        debuff_name = ability["debuff_name"] || "weakness"
        duration = ability["duration"] || 10_000
        stacks = ability["stacks"] || 1

        """
                debuff :#{debuff_name}, duration: #{duration}, stacks: #{stacks}
        """

      _ ->
        """
                telegraph :circle, radius: 5, duration: 2000, color: :red
                damage #{estimate_damage(level, :medium)}, type: :magic
        """
    end
    |> String.trim_trailing()
  end

  defp generate_effect(effect, level) do
    type = effect["type"] || effect[:type]

    case type do
      :telegraph -> generate_telegraph_effect(effect)
      "telegraph" -> generate_telegraph_effect(effect)
      :damage -> generate_damage_effect(effect, level)
      "damage" -> generate_damage_effect(effect, level)
      :debuff -> generate_debuff_effect(effect)
      "debuff" -> generate_debuff_effect(effect)
      :buff -> generate_buff_effect(effect)
      "buff" -> generate_buff_effect(effect)
      :movement -> generate_movement_effect(effect)
      "movement" -> generate_movement_effect(effect)
      :spawn -> generate_spawn_effect(effect)
      "spawn" -> generate_spawn_effect(effect)
      :coordination -> generate_coordination_effect(effect)
      "coordination" -> generate_coordination_effect(effect)
      _ -> "        # Unknown effect type: #{inspect(type)}"
    end
  end

  defp generate_telegraph_effect(effect) do
    shape = effect["shape"] || effect[:shape] || "circle"
    color = effect["color"] || effect[:color] || "red"
    duration = effect["duration"] || effect[:duration] || 2000

    params =
      case shape do
        s when s in [:circle, "circle"] ->
          radius = effect["radius"] || effect[:radius] || 5
          "radius: #{radius}"

        s when s in [:cone, "cone"] ->
          angle = effect["angle"] || effect[:angle] || 90
          length = effect["length"] || effect[:length] || 15
          "angle: #{angle}, length: #{length}"

        s when s in [:line, "line"] ->
          width = effect["width"] || effect[:width] || 3
          length = effect["length"] || effect[:length] || 20
          "width: #{width}, length: #{length}"

        s when s in [:donut, "donut"] ->
          inner = effect["inner_radius"] || effect[:inner_radius] || 5
          outer = effect["outer_radius"] || effect[:outer_radius] || 15
          "inner_radius: #{inner}, outer_radius: #{outer}"

        s when s in [:cross, "cross"] ->
          width = effect["width"] || effect[:width] || 3
          length = effect["length"] || effect[:length] || 20
          "width: #{width}, length: #{length}"

        s when s in [:room_wide, "room_wide"] ->
          ""

        _ ->
          radius = effect["radius"] || effect[:radius] || 5
          "radius: #{radius}"
      end

    shape_atom = safe_to_atom(shape, @valid_shapes, :circle)
    color_atom = safe_to_atom(color, @valid_colors, :red)

    if params == "" do
      "        telegraph :#{shape_atom}, duration: #{duration}, color: :#{color_atom}"
    else
      "        telegraph :#{shape_atom}, #{params}, duration: #{duration}, color: :#{color_atom}"
    end
  end

  defp generate_damage_effect(effect, default_level) do
    amount = effect["amount"] || effect[:amount] || estimate_damage(default_level, :medium)
    damage_type = effect["damage_type"] || effect[:damage_type] || "magic"
    type_atom = safe_to_atom(damage_type, @valid_damage_types, :magic)

    "        damage #{amount}, type: :#{type_atom}"
  end

  defp generate_debuff_effect(effect) do
    name = effect["name"] || effect[:name] || "weakness"
    duration = effect["duration"] || effect[:duration] || 10_000
    stacks = effect["stacks"] || effect[:stacks]

    name_atom = ability_to_atom_name(name)

    if stacks do
      "        debuff :#{name_atom}, duration: #{duration}, stacks: #{stacks}"
    else
      "        debuff :#{name_atom}, duration: #{duration}"
    end
  end

  defp generate_buff_effect(effect) do
    name = effect["name"] || effect[:name] || "enrage"
    duration = effect["duration"] || effect[:duration] || 10_000

    name_atom = ability_to_atom_name(name)

    "        buff :#{name_atom}, duration: #{duration}"
  end

  defp generate_movement_effect(effect) do
    movement_type = effect["movement_type"] || effect[:movement_type] || "knockback"
    distance = effect["distance"] || effect[:distance] || 10
    type_atom = safe_to_atom(movement_type, @valid_movement_types, :knockback)

    "        movement :#{type_atom}, distance: #{distance}"
  end

  defp generate_spawn_effect(effect) do
    spawn_type = effect["spawn_type"] || effect[:spawn_type] || "add"
    creature_id = effect["creature_id"] || effect[:creature_id] || 0
    count = effect["count"] || effect[:count] || 1
    type_atom = safe_to_atom(spawn_type, @valid_spawn_types, :add)

    "        spawn :#{type_atom}, creature_id: #{creature_id}, count: #{count}"
  end

  defp generate_coordination_effect(effect) do
    coord_type = effect["coordination_type"] || effect[:coordination_type] || "stack"
    type_atom = safe_to_atom(coord_type, @valid_coordination_types, :stack)

    case type_atom do
      :stack ->
        min_players = effect["min_players"] || effect[:min_players] || 3
        damage = effect["damage"] || effect[:damage] || 30_000
        "        coordination :stack, min_players: #{min_players}, damage: #{damage}"

      :spread ->
        distance = effect["required_distance"] || effect[:required_distance] || 8
        damage = effect["damage"] || effect[:damage] || 6000
        "        coordination :spread, required_distance: #{distance}, damage: #{damage}"

      _ ->
        "        coordination :#{type_atom}"
    end
  end

  defp ability_to_atom_name(name) when is_binary(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9\s]/, "")
    |> String.replace(~r/\s+/, "_")
  end

  defp ability_to_atom_name(name) when is_atom(name), do: name

  defp estimate_damage(level, intensity) do
    base =
      cond do
        level <= 20 -> 3000
        level <= 35 -> 8000
        level <= 50 -> 15_000
        true -> 25_000
      end

    multiplier =
      case intensity do
        :light -> 0.7
        :medium -> 1.0
        :heavy -> 1.8
        :coordination -> 3.0
        _ -> 1.0
      end

    round(base * multiplier)
  end

  defp format_number(n) when n >= 1_000_000 do
    millions = div(n, 1_000_000)
    remainder = rem(n, 1_000_000)
    thousands = div(remainder, 1_000)
    ones = rem(remainder, 1_000)
    "#{millions}_#{pad_number(thousands, 3)}_#{pad_number(ones, 3)}"
  end

  defp format_number(n) when n >= 1_000, do: "#{div(n, 1_000)}_#{rem(n, 1_000) |> pad_number(3)}"
  defp format_number(n), do: "#{n}"

  defp pad_number(n, digits) do
    n
    |> Integer.to_string()
    |> String.pad_leading(digits, "0")
  end

  defp format_code(code) do
    # Basic formatting - remove excessive blank lines
    code
    |> String.replace(~r/\n{3,}/, "\n\n")
    |> String.trim()
    |> Kernel.<>("\n")
  end
end
