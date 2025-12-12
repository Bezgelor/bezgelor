defmodule BezgelorWorld.PvP.Deserter do
  @moduledoc """
  Deserter debuff handling for players who leave PvP content early.

  Deserter prevents queueing for battlegrounds, arenas, and warplots
  for a period of time. Duration increases with repeat offenses.
  """

  @base_duration_ms 900_000
  @stack_multiplier 2.0
  @max_duration_ms 3_600_000
  @max_stacks 5

  defstruct [
    :player_guid,
    :stacks,
    :expires_at,
    :applied_at,
    :content_type
  ]

  @type content_type :: :battleground | :arena | :warplot

  @type t :: %__MODULE__{
          player_guid: non_neg_integer(),
          stacks: non_neg_integer(),
          expires_at: DateTime.t(),
          applied_at: DateTime.t(),
          content_type: content_type()
        }

  @doc """
  Applies or increases deserter debuff.
  """
  @spec apply(non_neg_integer(), content_type(), t() | nil) :: t()
  def apply(player_guid, content_type, existing \\ nil) do
    now = DateTime.utc_now()

    {stacks, base_time} =
      if existing && DateTime.compare(existing.expires_at, now) == :gt do
        # Still has deserter - stack it
        {min(existing.stacks + 1, @max_stacks), existing.expires_at}
      else
        # Fresh deserter
        {1, now}
      end

    duration_ms = calculate_duration(stacks)
    expires_at = DateTime.add(base_time, div(duration_ms, 1000), :second)

    %__MODULE__{
      player_guid: player_guid,
      stacks: stacks,
      expires_at: expires_at,
      applied_at: now,
      content_type: content_type
    }
  end

  @doc """
  Checks if player has active deserter.
  """
  @spec active?(t() | nil) :: boolean()
  def active?(nil), do: false

  def active?(deserter) do
    DateTime.compare(deserter.expires_at, DateTime.utc_now()) == :gt
  end

  @doc """
  Gets remaining deserter time in seconds.
  """
  @spec remaining_seconds(t() | nil) :: non_neg_integer()
  def remaining_seconds(nil), do: 0

  def remaining_seconds(deserter) do
    now = DateTime.utc_now()

    case DateTime.compare(deserter.expires_at, now) do
      :gt -> DateTime.diff(deserter.expires_at, now, :second)
      _ -> 0
    end
  end

  @doc """
  Clears deserter (e.g., after completing a match).
  """
  @spec clear(t() | nil) :: nil
  def clear(_deserter), do: nil

  @doc """
  Checks if a player can queue for content.
  """
  @spec can_queue?(t() | nil, content_type()) :: boolean()
  def can_queue?(nil, _content_type), do: true

  def can_queue?(deserter, content_type) do
    # Deserter applies to all content types in WildStar
    not active?(deserter) or deserter.content_type != content_type
  end

  @doc """
  Gets configuration values.
  """
  @spec base_duration_ms() :: non_neg_integer()
  def base_duration_ms, do: @base_duration_ms

  @spec max_duration_ms() :: non_neg_integer()
  def max_duration_ms, do: @max_duration_ms

  # Private functions

  defp calculate_duration(stacks) do
    duration = @base_duration_ms * :math.pow(@stack_multiplier, stacks - 1)
    round(min(duration, @max_duration_ms))
  end
end
