defmodule BezgelorCore.Death do
  @moduledoc """
  Pure functions for death mechanics.

  Handles death penalty calculations, respawn health percentages,
  and utility functions for the death/resurrection system.
  """

  import Bitwise

  # Player GUID type identifier (high 4 bits)
  @player_guid_type 0x10

  # Respawn grace period before forced respawn
  @respawn_grace_period_ms 30_000

  @doc """
  Calculate durability loss on death.

  Returns percentage of durability to remove from all equipped items.
  Lower level characters receive less harsh penalties.

  ## Examples

      iex> Death.durability_loss(5)
      0.0

      iex> Death.durability_loss(25)
      5.0

      iex> Death.durability_loss(45)
      10.0

      iex> Death.durability_loss(50)
      15.0
  """
  @spec durability_loss(level :: non_neg_integer()) :: float()
  def durability_loss(level) when level < 10, do: 0.0
  def durability_loss(level) when level < 30, do: 5.0
  def durability_loss(level) when level < 50, do: 10.0
  def durability_loss(_level), do: 15.0

  @doc """
  Calculate respawn health percentage.

  Higher level characters respawn with lower starting health at graveyard.
  This incentivizes accepting player resurrections over graveyard respawns.

  ## Examples

      iex> Death.respawn_health_percent(10)
      50.0

      iex> Death.respawn_health_percent(30)
      35.0

      iex> Death.respawn_health_percent(50)
      25.0
  """
  @spec respawn_health_percent(level :: non_neg_integer()) :: float()
  def respawn_health_percent(level) when level < 20, do: 50.0
  def respawn_health_percent(level) when level < 40, do: 35.0
  def respawn_health_percent(_level), do: 25.0

  @doc """
  Calculate health restored from a resurrection spell.

  Takes the target's max health and the spell's resurrection percentage,
  returns the actual health to restore.

  ## Examples

      iex> Death.resurrection_health(10000, 35.0)
      3500

      iex> Death.resurrection_health(10000, 100.0)
      10000
  """
  @spec resurrection_health(max_health :: non_neg_integer(), res_percent :: float()) ::
          non_neg_integer()
  def resurrection_health(max_health, res_percent) do
    clamped = max(0.0, min(res_percent, 100.0))
    round(max_health * clamped / 100.0)
  end

  @doc """
  Check if a GUID represents a player entity.

  Player GUIDs have 0x10 in the high type bits.
  """
  @spec is_player_guid?(guid :: non_neg_integer()) :: boolean()
  def is_player_guid?(guid) when is_integer(guid) do
    # Extract high 8 bits (type identifier)
    type = guid >>> 56
    type == @player_guid_type
  end

  @doc """
  Convert death type atom to protocol integer.

  ## Death Types
    - 0 = combat (killed by entity)
    - 1 = fall (fall damage)
    - 2 = drown (underwater too long)
    - 3 = environment (lava, hazards)
  """
  @spec death_type(type :: atom()) :: non_neg_integer()
  def death_type(:combat), do: 0
  def death_type(:fall), do: 1
  def death_type(:drown), do: 2
  def death_type(:environment), do: 3

  @doc """
  Get the respawn grace period in milliseconds.

  Players have this long to accept a resurrection or choose to respawn
  before being automatically respawned at their bindpoint.
  """
  @spec respawn_grace_period_ms() :: non_neg_integer()
  def respawn_grace_period_ms, do: @respawn_grace_period_ms
end
