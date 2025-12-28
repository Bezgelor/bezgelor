defmodule BezgelorWorld.Event.Territory do
  @moduledoc """
  Territory capture mechanics for public events.

  This module contains pure functions for:
  - Creating territory state from event definitions
  - Managing player presence in capture zones
  - Processing capture tick progress
  - Checking capture completion status

  ## Territory Control Events

  Territory control events have multiple capture points that players must
  contest. Players in a zone increase capture progress each tick. More
  players means faster capture (up to 5 players).

  ## Territory State Structure

  Territory state contains:
  - `territories` - List of territory points
  - `capture_tick_timer` - Timer reference for periodic ticks (or nil)

  ## Territory Point Structure

  Each territory point has:
  - `index` - Position in territories list (0-indexed)
  - `name` - Display name
  - `capture_progress` - Current progress (0-100)
  - `players_in_zone` - MapSet of character IDs in the zone
  - `captured` - Whether this point is fully captured
  """

  require Logger

  # Constants for capture mechanics
  @capture_tick_interval_ms 1_000
  @capture_progress_per_tick 5
  @capture_progress_max 100

  @type territory_point :: %{
          index: non_neg_integer(),
          name: String.t(),
          capture_progress: non_neg_integer(),
          players_in_zone: MapSet.t(non_neg_integer()),
          captured: boolean()
        }

  @type territory_state :: %{
          territories: [territory_point()],
          capture_tick_timer: reference() | nil
        }

  @doc """
  Returns the capture tick interval in milliseconds.
  """
  @spec capture_tick_interval_ms() :: non_neg_integer()
  def capture_tick_interval_ms, do: @capture_tick_interval_ms

  @doc """
  Create initial territory state from an event definition.

  ## Parameters

  - `event_def` - Event definition map with optional "territories" list

  ## Returns

  A new territory_state map with initialized territory points.
  """
  @spec create_territory_state(map()) :: territory_state()
  def create_territory_state(event_def) do
    territory_defs = event_def["territories"] || []

    territory_points =
      territory_defs
      |> Enum.with_index()
      |> Enum.map(fn {territory_def, index} ->
        %{
          index: index,
          name: territory_def["name"] || "Territory #{index + 1}",
          capture_progress: 0,
          players_in_zone: MapSet.new(),
          captured: false
        }
      end)

    %{
      territories: territory_points,
      capture_tick_timer: nil
    }
  end

  @doc """
  Check if an event has territory control mechanics.

  ## Parameters

  - `event_def` - Event definition map

  ## Returns

  `true` if the event uses territories, `false` otherwise.
  """
  @spec has_territories?(map()) :: boolean()
  def has_territories?(event_def) do
    territories = event_def["territories"] || []
    length(territories) > 0
  end

  @doc """
  Get a specific territory point by index.

  ## Parameters

  - `territory_state` - Current territory state (or nil)
  - `index` - Territory index to find

  ## Returns

  The territory point map, or nil if not found.
  """
  @spec get_territory_point(territory_state() | nil, non_neg_integer()) :: territory_point() | nil
  def get_territory_point(nil, _index), do: nil

  def get_territory_point(territory_state, index) do
    Enum.find(territory_state.territories, &(&1.index == index))
  end

  @doc """
  Update a territory point in the state.

  ## Parameters

  - `territory_state` - Current territory state
  - `index` - Territory index to update
  - `updated_territory` - New territory point data

  ## Returns

  Updated territory_state with the modified territory.
  """
  @spec update_territory_point(territory_state(), non_neg_integer(), territory_point()) ::
          territory_state()
  def update_territory_point(territory_state, index, updated_territory) do
    territories =
      Enum.map(territory_state.territories, fn territory ->
        if territory.index == index do
          updated_territory
        else
          territory
        end
      end)

    %{territory_state | territories: territories}
  end

  @doc """
  Add a player to a territory's capture zone.

  ## Parameters

  - `territory_state` - Current territory state
  - `territory_index` - Territory to add player to
  - `character_id` - Character ID entering the zone

  ## Returns

  `{:ok, updated_territory, updated_state}` or `{:error, :territory_not_found}`.
  """
  @spec add_player_to_territory(territory_state(), non_neg_integer(), non_neg_integer()) ::
          {:ok, territory_point(), territory_state()} | {:error, :territory_not_found}
  def add_player_to_territory(territory_state, territory_index, character_id) do
    case get_territory_point(territory_state, territory_index) do
      nil ->
        {:error, :territory_not_found}

      territory ->
        players = MapSet.put(territory.players_in_zone, character_id)
        updated_territory = %{territory | players_in_zone: players}
        updated_state = update_territory_point(territory_state, territory_index, updated_territory)
        {:ok, updated_territory, updated_state}
    end
  end

  @doc """
  Remove a player from a territory's capture zone.

  ## Parameters

  - `territory_state` - Current territory state
  - `territory_index` - Territory to remove player from
  - `character_id` - Character ID leaving the zone

  ## Returns

  `{:ok, updated_territory, updated_state}` or `{:error, :territory_not_found}`.
  """
  @spec remove_player_from_territory(territory_state(), non_neg_integer(), non_neg_integer()) ::
          {:ok, territory_point(), territory_state()} | {:error, :territory_not_found}
  def remove_player_from_territory(territory_state, territory_index, character_id) do
    case get_territory_point(territory_state, territory_index) do
      nil ->
        {:error, :territory_not_found}

      territory ->
        players = MapSet.delete(territory.players_in_zone, character_id)
        updated_territory = %{territory | players_in_zone: players}
        updated_state = update_territory_point(territory_state, territory_index, updated_territory)
        {:ok, updated_territory, updated_state}
    end
  end

  @doc """
  Process a capture tick, updating progress for all territories with players.

  Progress increases based on player count (up to 5 players for max speed).
  Territories are marked as captured when progress reaches 100.

  ## Parameters

  - `territory_state` - Current territory state

  ## Returns

  Updated territory_state with new capture progress.
  """
  @spec process_capture_tick(territory_state()) :: territory_state()
  def process_capture_tick(territory_state) do
    territories =
      Enum.map(territory_state.territories, fn territory ->
        player_count = MapSet.size(territory.players_in_zone)

        if player_count > 0 and not territory.captured do
          # More players = faster capture, up to 5x
          progress_increase = @capture_progress_per_tick * min(player_count, 5)

          new_progress =
            min(territory.capture_progress + progress_increase, @capture_progress_max)

          captured = new_progress >= @capture_progress_max

          if captured do
            Logger.info("Territory #{territory.index} (#{territory.name}) captured!")
          end

          %{territory | capture_progress: new_progress, captured: captured}
        else
          territory
        end
      end)

    %{territory_state | territories: territories}
  end

  @doc """
  Check if any territories have players present.

  ## Parameters

  - `territory_state` - Current territory state

  ## Returns

  `true` if any territory has players, `false` otherwise.
  """
  @spec any_players_in_territories?(territory_state()) :: boolean()
  def any_players_in_territories?(territory_state) do
    Enum.any?(territory_state.territories, fn territory ->
      MapSet.size(territory.players_in_zone) > 0
    end)
  end

  @doc """
  Check if all territories have been captured.

  ## Parameters

  - `territory_state` - Current territory state

  ## Returns

  `true` if all territories are captured, `false` otherwise.
  """
  @spec all_territories_captured?(territory_state()) :: boolean()
  def all_territories_captured?(territory_state) do
    Enum.all?(territory_state.territories, & &1.captured)
  end

  @doc """
  Count the number of captured territories.

  ## Parameters

  - `territory_state` - Current territory state

  ## Returns

  Number of captured territories.
  """
  @spec count_captured(territory_state()) :: non_neg_integer()
  def count_captured(territory_state) do
    Enum.count(territory_state.territories, & &1.captured)
  end

  @doc """
  Get the total number of territories.

  ## Parameters

  - `territory_state` - Current territory state

  ## Returns

  Total number of territories.
  """
  @spec total_territories(territory_state()) :: non_neg_integer()
  def total_territories(territory_state) do
    length(territory_state.territories)
  end

  @doc """
  Calculate overall capture progress as a percentage.

  ## Parameters

  - `territory_state` - Current territory state

  ## Returns

  Progress as integer percentage (0-100).
  """
  @spec overall_progress_percent(territory_state()) :: non_neg_integer()
  def overall_progress_percent(%{territories: []}) do
    100
  end

  def overall_progress_percent(territory_state) do
    total = length(territory_state.territories)

    total_progress =
      Enum.reduce(territory_state.territories, 0, fn territory, acc ->
        acc + territory.capture_progress
      end)

    div(total_progress, total)
  end

  @doc """
  Set the capture tick timer reference.

  ## Parameters

  - `territory_state` - Current territory state
  - `timer_ref` - Timer reference or nil

  ## Returns

  Updated territory_state with timer set.
  """
  @spec set_capture_tick_timer(territory_state(), reference() | nil) :: territory_state()
  def set_capture_tick_timer(territory_state, timer_ref) do
    %{territory_state | capture_tick_timer: timer_ref}
  end

  @doc """
  Get a summary of territory capture status.

  ## Parameters

  - `territory_state` - Current territory state

  ## Returns

  Map with territory status information.
  """
  @spec territory_summary(territory_state()) :: map()
  def territory_summary(territory_state) do
    %{
      total: total_territories(territory_state),
      captured: count_captured(territory_state),
      all_captured: all_territories_captured?(territory_state),
      progress_percent: overall_progress_percent(territory_state),
      territories:
        Enum.map(territory_state.territories, fn t ->
          %{
            index: t.index,
            name: t.name,
            progress: t.capture_progress,
            captured: t.captured,
            player_count: MapSet.size(t.players_in_zone)
          }
        end)
    }
  end
end
