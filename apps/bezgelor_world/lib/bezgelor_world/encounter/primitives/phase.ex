defmodule BezgelorWorld.Encounter.Primitives.Phase do
  @moduledoc """
  Phase transition primitives for boss encounters.

  Phases represent distinct stages of a boss fight, typically triggered
  by health thresholds. Each phase can have its own abilities, modifiers,
  and mechanics.

  ## Phase Transitions

  Phases transition based on health conditions:
  - `health_above: 70` - Active when boss > 70% health
  - `health_below: 30` - Active when boss < 30% health
  - `health_between: {30, 70}` - Active when 30% <= boss <= 70%

  ## Intermission Phases

  Some encounters have intermission phases that trigger at specific
  health thresholds but are time-limited:

      intermission :adds_phase, at_health: 50, duration: 30000 do
        spawn :wave, creature_id: 2001, count: 4
        boss_immune true
      end

  ## Phase Inheritance

  Phases can inherit abilities from previous phases:

      phase :three, health_below: 30 do
        inherit_phase :two
        # Phase two abilities plus new ones
      end
  """

  @doc """
  Defines an intermission phase that triggers at a specific health threshold.

  ## Options
    - `:at_health` - Health percentage to trigger (required)
    - `:duration` - How long the intermission lasts in ms (required)
    - `:repeatable` - Whether this can trigger multiple times (default: false)
  """
  defmacro intermission(name, opts, do: block) do
    quote do
      intermission_data = %{
        name: unquote(name),
        type: :intermission,
        trigger_health: Keyword.fetch!(unquote(opts), :at_health),
        duration: Keyword.fetch!(unquote(opts), :duration),
        repeatable: Keyword.get(unquote(opts), :repeatable, false),
        abilities: [],
        events: [],
        modifiers: %{}
      }

      Module.put_attribute(__MODULE__, :current_phase, intermission_data)
      unquote(block)
      phase_data = Module.get_attribute(__MODULE__, :current_phase)
      Module.put_attribute(__MODULE__, :phases, phase_data)
      Module.delete_attribute(__MODULE__, :current_phase)
    end
  end

  @doc """
  Makes the boss immune to damage during this phase.
  """
  defmacro boss_immune(value) do
    quote do
      phase = Module.get_attribute(__MODULE__, :current_phase)
      modifiers = Map.put(phase.modifiers, :immune, unquote(value))
      updated_phase = Map.put(phase, :modifiers, modifiers)
      Module.put_attribute(__MODULE__, :current_phase, updated_phase)
    end
  end

  @doc """
  Reduces damage taken by a percentage during this phase.
  """
  defmacro damage_reduction(percent) do
    quote do
      phase = Module.get_attribute(__MODULE__, :current_phase)
      modifiers = Map.put(phase.modifiers, :damage_reduction, unquote(percent))
      updated_phase = Map.put(phase, :modifiers, modifiers)
      Module.put_attribute(__MODULE__, :current_phase, updated_phase)
    end
  end

  @doc """
  Modifies attack speed for this phase.
  """
  defmacro attack_speed_modifier(multiplier) do
    quote do
      phase = Module.get_attribute(__MODULE__, :current_phase)
      modifiers = Map.put(phase.modifiers, :attack_speed, unquote(multiplier))
      updated_phase = Map.put(phase, :modifiers, modifiers)
      Module.put_attribute(__MODULE__, :current_phase, updated_phase)
    end
  end

  @doc """
  Modifies movement speed for this phase.
  """
  defmacro movement_speed_modifier(multiplier) do
    quote do
      phase = Module.get_attribute(__MODULE__, :current_phase)
      modifiers = Map.put(phase.modifiers, :movement_speed, unquote(multiplier))
      updated_phase = Map.put(phase, :modifiers, modifiers)
      Module.put_attribute(__MODULE__, :current_phase, updated_phase)
    end
  end

  @doc """
  Triggers an emote/announcement when entering this phase.
  """
  defmacro phase_emote(text) do
    quote do
      phase = Module.get_attribute(__MODULE__, :current_phase)
      updated_phase = Map.put(phase, :emote, unquote(text))
      Module.put_attribute(__MODULE__, :current_phase, updated_phase)
    end
  end

  @doc """
  Plays a sound/voice line when entering this phase.
  """
  defmacro phase_sound(sound_id) do
    quote do
      phase = Module.get_attribute(__MODULE__, :current_phase)
      updated_phase = Map.put(phase, :sound, unquote(sound_id))
      Module.put_attribute(__MODULE__, :current_phase, updated_phase)
    end
  end
end
