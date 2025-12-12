defmodule BezgelorWorld.PvP.Respawn do
  @moduledoc """
  Battleground respawn mechanics.

  Handles wave-based respawning and graveyard selection.
  """

  @base_respawn_time_ms 30_000
  @wave_respawn_interval_ms 15_000
  @graveyard_protection_ms 3_000

  defstruct [
    :player_guid,
    :faction,
    :death_time,
    :respawn_time,
    :graveyard_id,
    :protection_expires
  ]

  @type faction :: :exile | :dominion

  @type t :: %__MODULE__{
          player_guid: non_neg_integer(),
          faction: faction(),
          death_time: integer(),
          respawn_time: integer(),
          graveyard_id: non_neg_integer() | nil,
          protection_expires: integer() | nil
        }

  @type graveyard :: %{
          id: non_neg_integer(),
          position: {float(), float(), float()},
          faction: faction() | :neutral,
          priority: integer()
        }

  @doc """
  Creates a respawn entry for a player who died.
  """
  @spec create(non_neg_integer(), faction()) :: t()
  def create(player_guid, faction) do
    now = System.monotonic_time(:millisecond)
    respawn_time = calculate_respawn_time(now)

    %__MODULE__{
      player_guid: player_guid,
      faction: faction,
      death_time: now,
      respawn_time: respawn_time,
      graveyard_id: nil,
      protection_expires: nil
    }
  end

  @doc """
  Calculate when player will respawn (wave-based).
  """
  @spec calculate_respawn_time(integer(), integer()) :: integer()
  def calculate_respawn_time(death_time, wave_interval \\ @wave_respawn_interval_ms) do
    # Find next wave after minimum respawn time
    min_respawn = death_time + @base_respawn_time_ms
    wave_number = div(min_respawn, wave_interval) + 1
    wave_number * wave_interval
  end

  @doc """
  Check if player can respawn now.
  """
  @spec can_respawn?(t()) :: boolean()
  def can_respawn?(respawn) do
    System.monotonic_time(:millisecond) >= respawn.respawn_time
  end

  @doc """
  Get time until respawn in milliseconds.
  """
  @spec time_until_respawn(t()) :: integer()
  def time_until_respawn(respawn) do
    now = System.monotonic_time(:millisecond)
    max(0, respawn.respawn_time - now)
  end

  @doc """
  Select graveyard based on faction and controlled points.
  """
  @spec select_graveyard(faction(), [graveyard()]) :: graveyard() | nil
  def select_graveyard(faction, graveyards) do
    # Prefer closest graveyard that faction controls
    faction_graveyards =
      graveyards
      |> Enum.filter(fn g -> g.faction == faction or g.faction == :neutral end)
      |> Enum.sort_by(fn g -> g.priority end, :desc)

    case faction_graveyards do
      [best | _] -> best
      # Fallback to base graveyard
      [] -> Enum.find(graveyards, fn g -> g.faction == faction end)
    end
  end

  @doc """
  Apply respawn protection.
  """
  @spec apply_protection(t()) :: t()
  def apply_protection(respawn) do
    %{respawn | protection_expires: System.monotonic_time(:millisecond) + @graveyard_protection_ms}
  end

  @doc """
  Check if player still has respawn protection.
  """
  @spec has_protection?(t()) :: boolean()
  def has_protection?(respawn) do
    respawn.protection_expires != nil and
      System.monotonic_time(:millisecond) < respawn.protection_expires
  end

  @doc """
  Get configuration values.
  """
  @spec base_respawn_time_ms() :: non_neg_integer()
  def base_respawn_time_ms, do: @base_respawn_time_ms

  @spec wave_interval_ms() :: non_neg_integer()
  def wave_interval_ms, do: @wave_respawn_interval_ms

  @spec protection_duration_ms() :: non_neg_integer()
  def protection_duration_ms, do: @graveyard_protection_ms
end
