defmodule BezgelorWorld.Encounter.DSL do
  @moduledoc """
  Domain-Specific Language for declarative boss encounter definition.

  This module provides macros that allow boss encounters to be defined
  in a clean, readable format that closely mirrors game design documents.

  ## Example Usage

      defmodule BezgelorWorld.Encounter.Bosses.Stormtalon do
        use BezgelorWorld.Encounter.DSL

        boss "Stormtalon" do
          boss_id 1001
          health 500_000
          level 20
          enrage_timer 480_000

          phase :one, health_above: 70 do
            ability :lightning_strike, cooldown: 8000, target: :random do
              telegraph :circle, radius: 5, duration: 2000
              damage 5000, type: :magic
            end

            ability :static_charge, cooldown: 15000, target: :tank do
              debuff :static, duration: 10000, stacks: 3
            end
          end

          phase :two, health_between: {30, 70} do
            inherit_phase :one

            ability :eye_of_the_storm, cooldown: 25000 do
              telegraph :donut, inner_radius: 10, outer_radius: 20
              spawn :add, creature_id: 2001, count: 2
            end
          end

          phase :three, health_below: 30 do
            inherit_phase :two
            enrage_modifier 1.5

            ability :tempest, cooldown: 12000 do
              telegraph :room_wide
              movement :knockback, distance: 15
            end
          end

          on_death do
            loot_table 1001
            achievement 5001
          end
        end
      end
  """

  @type health_condition ::
          {:health_above, number()}
          | {:health_below, number()}
          | {:health_between, {number(), number()}}

  @type target_type ::
          :tank
          | :healer
          | :random
          | :farthest
          | :nearest
          | :highest_threat
          | :lowest_health
          | :all

  @type telegraph_shape :: :circle | :cone | :line | :donut | :room_wide | :cross

  @type damage_type :: :physical | :magic | :nature | :fire | :ice | :arcane

  @doc """
  Use this module to enable the encounter DSL in your boss definition module.

  Options:
    - `:validate` - Whether to validate the encounter at compile time (default: true)
  """
  defmacro __using__(opts) do
    validate = Keyword.get(opts, :validate, true)

    quote do
      import BezgelorWorld.Encounter.DSL
      import BezgelorWorld.Encounter.Primitives.Phase
      import BezgelorWorld.Encounter.Primitives.Telegraph
      import BezgelorWorld.Encounter.Primitives.Target
      import BezgelorWorld.Encounter.Primitives.Spawn
      import BezgelorWorld.Encounter.Primitives.Movement
      import BezgelorWorld.Encounter.Primitives.Interrupt
      import BezgelorWorld.Encounter.Primitives.Environmental
      import BezgelorWorld.Encounter.Primitives.Coordination

      Module.register_attribute(__MODULE__, :encounter_data, accumulate: false)
      Module.register_attribute(__MODULE__, :current_phase, accumulate: false)
      Module.register_attribute(__MODULE__, :phases, accumulate: true)
      Module.register_attribute(__MODULE__, :abilities, accumulate: true)
      Module.register_attribute(__MODULE__, :events, accumulate: true)
      Module.register_attribute(__MODULE__, :validate_encounter, accumulate: false)

      Module.put_attribute(__MODULE__, :validate_encounter, unquote(validate))

      @before_compile BezgelorWorld.Encounter.DSL
    end
  end

  defmacro __before_compile__(env) do
    encounter_data = Module.get_attribute(env.module, :encounter_data) || %{}
    phases = Module.get_attribute(env.module, :phases) || []
    events = Module.get_attribute(env.module, :events) || []
    validate = Module.get_attribute(env.module, :validate_encounter)

    # Reverse phases to maintain definition order
    phases = Enum.reverse(phases)

    encounter =
      Map.merge(encounter_data, %{
        phases: phases,
        events: events,
        module: env.module
      })

    if validate do
      validate_encounter!(encounter, env)
    end

    quote do
      @doc """
      Returns the compiled encounter definition.
      """
      def encounter, do: unquote(Macro.escape(encounter))

      @doc """
      Returns the boss ID for this encounter.
      """
      def boss_id, do: unquote(encounter_data[:boss_id])

      @doc """
      Returns the boss name.
      """
      def boss_name, do: unquote(encounter_data[:name])

      @doc """
      Returns all phases in order.
      """
      def phases, do: unquote(Macro.escape(phases))

      @doc """
      Returns the phase definition for a given phase name.
      """
      def get_phase(name) do
        Enum.find(phases(), fn p -> p.name == name end)
      end

      @doc """
      Determines the current phase based on health percentage.
      """
      def phase_for_health(health_percent) do
        phases()
        |> Enum.find(fn phase ->
          check_health_condition(phase.condition, health_percent)
        end)
      end

      defp check_health_condition({:health_above, threshold}, health) do
        health > threshold
      end

      defp check_health_condition({:health_below, threshold}, health) do
        health < threshold
      end

      defp check_health_condition({:health_between, {low, high}}, health) do
        health >= low and health <= high
      end

      defp check_health_condition(:always, _health), do: true
      defp check_health_condition(nil, _health), do: true
    end
  end

  @doc """
  Defines a boss encounter with the given name and configuration block.
  """
  defmacro boss(name, do: block) do
    quote do
      Module.put_attribute(__MODULE__, :encounter_data, %{name: unquote(name)})
      unquote(block)
    end
  end

  @doc """
  Sets the boss ID for data lookups.
  """
  defmacro boss_id(id) do
    quote do
      data = Module.get_attribute(__MODULE__, :encounter_data) || %{}
      Module.put_attribute(__MODULE__, :encounter_data, Map.put(data, :boss_id, unquote(id)))
    end
  end

  @doc """
  Sets the base health for the boss.
  """
  defmacro health(amount) do
    quote do
      data = Module.get_attribute(__MODULE__, :encounter_data) || %{}
      Module.put_attribute(__MODULE__, :encounter_data, Map.put(data, :health, unquote(amount)))
    end
  end

  @doc """
  Sets the boss level.
  """
  defmacro level(lvl) do
    quote do
      data = Module.get_attribute(__MODULE__, :encounter_data) || %{}
      Module.put_attribute(__MODULE__, :encounter_data, Map.put(data, :level, unquote(lvl)))
    end
  end

  @doc """
  Sets the enrage timer in milliseconds.
  """
  defmacro enrage_timer(ms) do
    quote do
      data = Module.get_attribute(__MODULE__, :encounter_data) || %{}
      Module.put_attribute(__MODULE__, :encounter_data, Map.put(data, :enrage_timer, unquote(ms)))
    end
  end

  @doc """
  Sets the interrupt armor count.
  """
  defmacro interrupt_armor(count) do
    quote do
      data = Module.get_attribute(__MODULE__, :encounter_data) || %{}

      Module.put_attribute(
        __MODULE__,
        :encounter_data,
        Map.put(data, :interrupt_armor, unquote(count))
      )
    end
  end

  @doc """
  Defines a phase of the encounter with health-based transition conditions.

  ## Options
    - `:health_above` - Phase active when health > threshold
    - `:health_below` - Phase active when health < threshold
    - `:health_between` - Phase active when health in range {low, high}
    - `:always` - Phase is always active (for intermission/special phases)
  """
  defmacro phase(name, opts \\ [], do: block) do
    condition = extract_condition(opts)

    quote do
      Module.put_attribute(__MODULE__, :current_phase, %{
        name: unquote(name),
        condition: unquote(Macro.escape(condition)),
        abilities: [],
        events: [],
        inherits: nil,
        modifiers: %{}
      })

      unquote(block)

      phase_data = Module.get_attribute(__MODULE__, :current_phase)
      Module.put_attribute(__MODULE__, :phases, phase_data)
      Module.delete_attribute(__MODULE__, :current_phase)
    end
  end

  @doc """
  Defines an ability within a phase.

  ## Options
    - `:cooldown` - Cooldown in milliseconds
    - `:cast_time` - Cast time in milliseconds (default: 0 for instant)
    - `:target` - Target selection type
    - `:interruptible` - Whether the ability can be interrupted

  Can be used with or without a block:

      # With block (for abilities with effects)
      ability :lightning_strike, cooldown: 8000 do
        telegraph :circle, radius: 5
        damage 5000, type: :magic
      end

      # Without block (simple ability)
      ability :melee_swing, cooldown: 2000, target: :tank
  """
  # With do block as separate argument (do ... end syntax)
  defmacro ability(name, opts, do: block) do
    quote do
      current_ability = %{
        name: unquote(name),
        cooldown: Keyword.get(unquote(opts), :cooldown, 0),
        cast_time: Keyword.get(unquote(opts), :cast_time, 0),
        target: Keyword.get(unquote(opts), :target, :tank),
        interruptible: Keyword.get(unquote(opts), :interruptible, false),
        effects: []
      }

      Module.put_attribute(__MODULE__, :current_ability, current_ability)
      unquote(block)
      ability_data = Module.get_attribute(__MODULE__, :current_ability)
      Module.delete_attribute(__MODULE__, :current_ability)

      phase = Module.get_attribute(__MODULE__, :current_phase)
      updated_phase = Map.update!(phase, :abilities, &[ability_data | &1])
      Module.put_attribute(__MODULE__, :current_phase, updated_phase)
    end
  end

  # Without do block (simple ability)
  defmacro ability(name, opts) when is_list(opts) do
    {block, opts} = Keyword.pop(opts, :do)

    if block do
      # Inline do: syntax
      quote do
        current_ability = %{
          name: unquote(name),
          cooldown: Keyword.get(unquote(opts), :cooldown, 0),
          cast_time: Keyword.get(unquote(opts), :cast_time, 0),
          target: Keyword.get(unquote(opts), :target, :tank),
          interruptible: Keyword.get(unquote(opts), :interruptible, false),
          effects: []
        }

        Module.put_attribute(__MODULE__, :current_ability, current_ability)
        unquote(block)
        ability_data = Module.get_attribute(__MODULE__, :current_ability)
        Module.delete_attribute(__MODULE__, :current_ability)

        phase = Module.get_attribute(__MODULE__, :current_phase)
        updated_phase = Map.update!(phase, :abilities, &[ability_data | &1])
        Module.put_attribute(__MODULE__, :current_phase, updated_phase)
      end
    else
      # No block at all
      quote do
        ability_data = %{
          name: unquote(name),
          cooldown: Keyword.get(unquote(opts), :cooldown, 0),
          cast_time: Keyword.get(unquote(opts), :cast_time, 0),
          target: Keyword.get(unquote(opts), :target, :tank),
          interruptible: Keyword.get(unquote(opts), :interruptible, false),
          effects: []
        }

        phase = Module.get_attribute(__MODULE__, :current_phase)
        updated_phase = Map.update!(phase, :abilities, &[ability_data | &1])
        Module.put_attribute(__MODULE__, :current_phase, updated_phase)
      end
    end
  end

  # Just name, no options
  defmacro ability(name) do
    quote do
      ability_data = %{
        name: unquote(name),
        cooldown: 0,
        cast_time: 0,
        target: :tank,
        interruptible: false,
        effects: []
      }

      phase = Module.get_attribute(__MODULE__, :current_phase)
      updated_phase = Map.update!(phase, :abilities, &[ability_data | &1])
      Module.put_attribute(__MODULE__, :current_phase, updated_phase)
    end
  end

  @doc """
  Adds a damage effect to the current ability.
  """
  defmacro damage(amount, opts \\ []) do
    quote do
      effect = %{
        type: :damage,
        amount: unquote(amount),
        damage_type: Keyword.get(unquote(opts), :type, :physical),
        periodic: Keyword.get(unquote(opts), :periodic, false),
        tick_interval: Keyword.get(unquote(opts), :tick_interval, 1000)
      }

      ability = Module.get_attribute(__MODULE__, :current_ability)
      updated = Map.update!(ability, :effects, &[effect | &1])
      Module.put_attribute(__MODULE__, :current_ability, updated)
    end
  end

  @doc """
  Adds a debuff effect to the current ability.
  """
  defmacro debuff(name, opts \\ []) do
    quote do
      effect = %{
        type: :debuff,
        name: unquote(name),
        duration: Keyword.get(unquote(opts), :duration, 10000),
        stacks: Keyword.get(unquote(opts), :stacks, 1),
        damage_per_tick: Keyword.get(unquote(opts), :damage_per_tick, 0),
        tick_interval: Keyword.get(unquote(opts), :tick_interval, 1000)
      }

      ability = Module.get_attribute(__MODULE__, :current_ability)
      updated = Map.update!(ability, :effects, &[effect | &1])
      Module.put_attribute(__MODULE__, :current_ability, updated)
    end
  end

  @doc """
  Adds a buff effect to the current ability (typically for boss self-buffs).
  """
  defmacro buff(name, opts \\ []) do
    quote do
      effect = %{
        type: :buff,
        name: unquote(name),
        duration: Keyword.get(unquote(opts), :duration, 10000),
        stacks: Keyword.get(unquote(opts), :stacks, 1),
        stat_modifiers: Keyword.get(unquote(opts), :modifiers, %{})
      }

      ability = Module.get_attribute(__MODULE__, :current_ability)
      updated = Map.update!(ability, :effects, &[effect | &1])
      Module.put_attribute(__MODULE__, :current_ability, updated)
    end
  end

  @doc """
  Adds a heal effect (for boss self-heals or mechanics that require healing).
  """
  defmacro heal(amount, opts \\ []) do
    quote do
      effect = %{
        type: :heal,
        amount: unquote(amount),
        target: Keyword.get(unquote(opts), :target, :self),
        periodic: Keyword.get(unquote(opts), :periodic, false),
        tick_interval: Keyword.get(unquote(opts), :tick_interval, 1000)
      }

      ability = Module.get_attribute(__MODULE__, :current_ability)
      updated = Map.update!(ability, :effects, &[effect | &1])
      Module.put_attribute(__MODULE__, :current_ability, updated)
    end
  end

  @doc """
  Defines the loot table to use on boss death.
  """
  defmacro loot_table(id) do
    quote do
      event = %{type: :on_death, action: :loot_table, value: unquote(id)}
      Module.put_attribute(__MODULE__, :events, event)
    end
  end

  @doc """
  Defines an achievement to award on boss defeat.
  """
  defmacro achievement(id) do
    quote do
      event = %{type: :on_death, action: :achievement, value: unquote(id)}
      Module.put_attribute(__MODULE__, :events, event)
    end
  end

  @doc """
  Defines actions to execute when the boss is defeated.
  """
  defmacro on_death(do: block) do
    quote do
      unquote(block)
    end
  end

  @doc """
  Defines actions to execute when the boss is engaged.
  """
  defmacro on_engage(do: block) do
    quote do
      Module.put_attribute(__MODULE__, :current_event_type, :on_engage)
      unquote(block)
      Module.delete_attribute(__MODULE__, :current_event_type)
    end
  end

  @doc """
  Defines actions to execute on a wipe (all players dead).
  """
  defmacro on_wipe(do: block) do
    quote do
      Module.put_attribute(__MODULE__, :current_event_type, :on_wipe)
      unquote(block)
      Module.delete_attribute(__MODULE__, :current_event_type)
    end
  end

  @doc """
  Inherits abilities from another phase.
  """
  defmacro inherit_phase(phase_name) do
    quote do
      phase = Module.get_attribute(__MODULE__, :current_phase)
      updated_phase = Map.put(phase, :inherits, unquote(phase_name))
      Module.put_attribute(__MODULE__, :current_phase, updated_phase)
    end
  end

  @doc """
  Sets a damage/speed modifier for the current phase (for soft enrage).
  """
  defmacro enrage_modifier(multiplier) do
    quote do
      phase = Module.get_attribute(__MODULE__, :current_phase)
      modifiers = Map.put(phase.modifiers, :enrage, unquote(multiplier))
      updated_phase = Map.put(phase, :modifiers, modifiers)
      Module.put_attribute(__MODULE__, :current_phase, updated_phase)
    end
  end

  # Private helper to extract health condition from options
  defp extract_condition(opts) do
    cond do
      Keyword.has_key?(opts, :health_above) ->
        {:health_above, Keyword.get(opts, :health_above)}

      Keyword.has_key?(opts, :health_below) ->
        {:health_below, Keyword.get(opts, :health_below)}

      Keyword.has_key?(opts, :health_between) ->
        {:health_between, Keyword.get(opts, :health_between)}

      Keyword.has_key?(opts, :always) ->
        :always

      true ->
        nil
    end
  end

  # Compile-time validation
  defp validate_encounter!(encounter, env) do
    errors = []

    errors =
      if is_nil(encounter[:boss_id]) do
        ["boss_id is required" | errors]
      else
        errors
      end

    errors =
      if is_nil(encounter[:name]) do
        ["boss name is required" | errors]
      else
        errors
      end

    errors =
      if Enum.empty?(encounter[:phases] || []) do
        ["at least one phase is required" | errors]
      else
        errors
      end

    unless Enum.empty?(errors) do
      raise CompileError,
        file: env.file,
        line: env.line,
        description: "Invalid encounter definition: #{Enum.join(errors, ", ")}"
    end
  end
end
