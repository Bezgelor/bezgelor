defmodule BezgelorWorld.Encounter.Primitives.Interrupt do
  @moduledoc """
  Interrupt armor system primitives for boss encounters.

  WildStar uses an "interrupt armor" system where bosses have a shield
  of interrupt points that must be broken before they can be interrupted.
  This creates coordinated interrupt gameplay.

  ## Interrupt Armor

  Bosses start with N stacks of interrupt armor. Each player interrupt
  removes one stack. When armor reaches 0, the boss is interrupted and
  enters a vulnerable state (Moment of Opportunity).

  ## Moment of Opportunity (MoO)

  When a boss is interrupted, they become vulnerable:
  - Take increased damage
  - Cannot cast abilities
  - Duration varies by encounter

  ## Example Usage

      boss "Stormtalon" do
        interrupt_armor 2

        phase :one, health_above: 70 do
          ability :devastating_attack, cast_time: 4000, interruptible: true do
            interrupt_required true
            on_interrupt :stun, duration: 5000
            on_cast_complete do
              damage 50000, type: :physical  # One-shot if not interrupted
            end
          end
        end
      end
  """

  @doc """
  Marks an ability as requiring interrupt (must be interrupted or wipe).
  """
  defmacro interrupt_required(value \\ true) do
    quote do
      ability = Module.get_attribute(__MODULE__, :current_ability)
      updated = Map.put(ability, :interrupt_required, unquote(value))
      Module.put_attribute(__MODULE__, :current_ability, updated)
    end
  end

  @doc """
  Defines what happens when the ability is successfully interrupted.

  ## Options
    - `:stun` - Boss is stunned
    - `:vulnerable` - Boss takes increased damage
    - `:custom` - Custom effect defined in block
  """
  defmacro on_interrupt(effect_type, opts \\ []) do
    quote do
      interrupt_effect = build_interrupt_effect(unquote(effect_type), unquote(opts))

      ability = Module.get_attribute(__MODULE__, :current_ability)
      updated = Map.put(ability, :on_interrupt, interrupt_effect)
      Module.put_attribute(__MODULE__, :current_ability, updated)
    end
  end

  @doc """
  Builds interrupt effect parameters.
  """
  def build_interrupt_effect(:stun, opts) do
    %{
      type: :stun,
      duration: Keyword.get(opts, :duration, 3000)
    }
  end

  def build_interrupt_effect(:vulnerable, opts) do
    %{
      type: :vulnerable,
      duration: Keyword.get(opts, :duration, 5000),
      damage_increase: Keyword.get(opts, :damage_increase, 50)
    }
  end

  def build_interrupt_effect(:moo, opts) do
    %{
      type: :moment_of_opportunity,
      duration: Keyword.get(opts, :duration, 5000),
      damage_increase: Keyword.get(opts, :damage_increase, 100),
      prevents_abilities: true
    }
  end

  def build_interrupt_effect(:knockdown, opts) do
    %{
      type: :knockdown,
      duration: Keyword.get(opts, :duration, 2000)
    }
  end

  def build_interrupt_effect(:phase_skip, opts) do
    %{
      type: :phase_skip,
      skip_to: Keyword.fetch!(opts, :skip_to)
    }
  end

  @doc """
  Defines what happens if the cast completes (not interrupted).
  """
  defmacro on_cast_complete(do: block) do
    quote do
      Module.put_attribute(__MODULE__, :in_cast_complete, true)
      unquote(block)
      Module.delete_attribute(__MODULE__, :in_cast_complete)
    end
  end

  @doc """
  Sets custom interrupt armor for a specific ability.
  (Overrides boss default)
  """
  defmacro ability_interrupt_armor(count) do
    quote do
      ability = Module.get_attribute(__MODULE__, :current_ability)
      updated = Map.put(ability, :interrupt_armor, unquote(count))
      Module.put_attribute(__MODULE__, :current_ability, updated)
    end
  end

  @doc """
  Makes the ability completely uninterruptible.
  """
  defmacro uninterruptible do
    quote do
      ability = Module.get_attribute(__MODULE__, :current_ability)

      updated =
        ability
        |> Map.put(:interruptible, false)
        |> Map.put(:interrupt_armor, :infinite)

      Module.put_attribute(__MODULE__, :current_ability, updated)
    end
  end

  @doc """
  Creates a cast bar for the ability.

  ## Options
    - `:name` - Display name for cast bar
    - `:color` - Cast bar color (:red for must-interrupt, :yellow for interruptible)
    - `:show_interrupt_armor` - Whether to show IA stacks
  """
  defmacro cast_bar(opts \\ []) do
    quote do
      cast_bar_data = %{
        name: Keyword.get(unquote(opts), :name),
        color: Keyword.get(unquote(opts), :color, :yellow),
        show_interrupt_armor: Keyword.get(unquote(opts), :show_interrupt_armor, true)
      }

      ability = Module.get_attribute(__MODULE__, :current_ability)
      updated = Map.put(ability, :cast_bar, cast_bar_data)
      Module.put_attribute(__MODULE__, :current_ability, updated)
    end
  end

  @doc """
  Defines a channeled ability that can be interrupted at any point.

  ## Options
    - `:duration` - Total channel duration
    - `:tick_interval` - How often effect triggers during channel
    - `:partial_effect` - Whether partial channel has partial effect
  """
  defmacro channeled(opts \\ []) do
    quote do
      channel_data = %{
        duration: Keyword.fetch!(unquote(opts), :duration),
        tick_interval: Keyword.get(unquote(opts), :tick_interval, 1000),
        partial_effect: Keyword.get(unquote(opts), :partial_effect, true),
        interruptible: true
      }

      ability = Module.get_attribute(__MODULE__, :current_ability)

      updated =
        ability
        |> Map.put(:channel, channel_data)
        |> Map.put(:interruptible, true)

      Module.put_attribute(__MODULE__, :current_ability, updated)
    end
  end

  @doc """
  Restores interrupt armor stacks to the boss.
  Useful for mechanics that reset interrupt armor mid-fight.
  """
  defmacro restore_interrupt_armor(count) do
    quote do
      effect = %{
        type: :restore_interrupt_armor,
        count: unquote(count)
      }

      ability = Module.get_attribute(__MODULE__, :current_ability)
      updated = Map.update!(ability, :effects, &[effect | &1])
      Module.put_attribute(__MODULE__, :current_ability, updated)
    end
  end
end
