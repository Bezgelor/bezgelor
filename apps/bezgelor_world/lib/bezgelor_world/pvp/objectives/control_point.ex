defmodule BezgelorWorld.PvP.Objectives.ControlPoint do
  @moduledoc """
  Halls of the Bloodsworn control point mechanics.

  Control points can be captured by standing in the capture zone.
  Multiple players capture faster, but there are diminishing returns.
  Contested points (both factions present) freeze capture progress.
  """

  @capture_time_ms 8_000
  @capture_speed_per_player 1.0
  @capture_speed_bonus 0.5
  @max_capture_players 3

  defstruct [
    :id,
    :name,
    :position,
    :owner,
    :capture_progress,
    :capturing_faction,
    :players_in_range,
    :score_multiplier
  ]

  @type faction :: :exile | :dominion | :neutral

  @type t :: %__MODULE__{
          id: non_neg_integer(),
          name: String.t(),
          position: {float(), float(), float()},
          owner: faction(),
          capture_progress: float(),
          capturing_faction: faction() | nil,
          players_in_range: %{exile: [non_neg_integer()], dominion: [non_neg_integer()]},
          score_multiplier: float()
        }

  @doc """
  Creates a new control point.
  """
  @spec new(non_neg_integer(), String.t(), {float(), float(), float()}, keyword()) :: t()
  def new(id, name, position, opts \\ []) do
    %__MODULE__{
      id: id,
      name: name,
      position: position,
      owner: Keyword.get(opts, :owner, :neutral),
      capture_progress: Keyword.get(opts, :capture_progress, 0.0),
      capturing_faction: nil,
      players_in_range: %{exile: [], dominion: []},
      score_multiplier: Keyword.get(opts, :score_multiplier, 1.0)
    }
  end

  @doc """
  Updates the players in range of this control point.
  """
  @spec update_players(t(), [non_neg_integer()], [non_neg_integer()]) :: t()
  def update_players(point, exile_players, dominion_players) do
    %{point | players_in_range: %{exile: exile_players, dominion: dominion_players}}
  end

  @doc """
  Process capture tick (called every second).

  Returns:
  - `{:contested, point}` when both factions present
  - `{:captured, point}` when a faction completes capture
  - `{:capturing, point}` when capture is in progress
  - `{:neutralized, point}` when point becomes neutral
  - `{:reversing, point}` when capture is being reversed
  - `{:owned, point}` when owning faction is on point
  - `{:unchanged, point}` when point is empty
  """
  @spec tick(t()) ::
          {:contested | :captured | :capturing | :neutralized | :reversing | :owned | :unchanged,
           t()}
  def tick(point) do
    exile_count = length(point.players_in_range.exile)
    dominion_count = length(point.players_in_range.dominion)

    cond do
      # Contested - no progress
      exile_count > 0 and dominion_count > 0 ->
        {:contested, point}

      # Exile capturing
      exile_count > 0 ->
        progress = calculate_capture_progress(exile_count)
        update_capture(point, :exile, progress)

      # Dominion capturing
      dominion_count > 0 ->
        progress = calculate_capture_progress(dominion_count)
        update_capture(point, :dominion, progress)

      # Empty - maintain current state
      true ->
        {:unchanged, point}
    end
  end

  @doc """
  Calculate points scored per tick for this control point.
  """
  @spec score_per_tick(t(), non_neg_integer()) :: non_neg_integer()
  def score_per_tick(point, base_score) do
    if point.owner in [:exile, :dominion] do
      round(base_score * point.score_multiplier)
    else
      0
    end
  end

  # Private functions

  defp calculate_capture_progress(player_count) do
    capped = min(player_count, @max_capture_players)
    base = @capture_speed_per_player
    bonus = @capture_speed_bonus * (capped - 1)
    (base + bonus) / (@capture_time_ms / 1000)
  end

  defp update_capture(point, faction, progress_delta) do
    cond do
      # Same faction owns it - already at 100%
      point.owner == faction ->
        {:owned, point}

      # Capturing towards this faction
      point.capturing_faction == faction or point.capturing_faction == nil ->
        new_progress = min(1.0, point.capture_progress + progress_delta)
        point = %{point | capture_progress: new_progress, capturing_faction: faction}

        if new_progress >= 1.0 do
          {:captured,
           %{point | owner: faction, capture_progress: 1.0, capturing_faction: nil}}
        else
          {:capturing, point}
        end

      # Reversing capture - must neutralize first
      true ->
        new_progress = max(0.0, point.capture_progress - progress_delta)
        point = %{point | capture_progress: new_progress}

        if new_progress <= 0.0 do
          # Neutralized - now can capture
          {:neutralized, %{point | owner: :neutral, capturing_faction: faction}}
        else
          {:reversing, point}
        end
    end
  end
end
