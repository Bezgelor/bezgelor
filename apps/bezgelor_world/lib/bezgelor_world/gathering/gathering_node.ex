defmodule BezgelorWorld.Gathering.GatheringNode do
  @moduledoc """
  Represents a gatherable resource node in the world.

  Nodes spawn at fixed positions, can be tapped (claimed) by players,
  and respawn after a timer when harvested.
  """

  @tap_duration_seconds 10

  defstruct [
    :node_id,
    :node_type_id,
    :position,
    :respawn_at,
    :tapped_by,
    :tap_expires_at
  ]

  @type t :: %__MODULE__{
          node_id: integer(),
          node_type_id: integer(),
          position: {float(), float(), float()},
          respawn_at: DateTime.t() | nil,
          tapped_by: integer() | nil,
          tap_expires_at: DateTime.t() | nil
        }

  @doc """
  Create a new gathering node.
  """
  @spec new(integer(), integer(), {float(), float(), float()}) :: t()
  def new(node_id, node_type_id, position) do
    %__MODULE__{
      node_id: node_id,
      node_type_id: node_type_id,
      position: position
    }
  end

  @doc """
  Check if the node is available for gathering.
  """
  @spec available?(t()) :: boolean()
  def available?(%__MODULE__{} = node) do
    not respawning?(node) and not actively_tapped?(node)
  end

  @doc """
  Check if node is currently respawning.
  """
  @spec respawning?(t()) :: boolean()
  def respawning?(%__MODULE__{respawn_at: nil}), do: false

  def respawning?(%__MODULE__{respawn_at: respawn_at}) do
    DateTime.compare(DateTime.utc_now(), respawn_at) == :lt
  end

  @doc """
  Check if node is actively tapped by someone.
  """
  @spec actively_tapped?(t()) :: boolean()
  def actively_tapped?(%__MODULE__{tapped_by: nil}), do: false
  def actively_tapped?(%__MODULE__{tap_expires_at: nil}), do: false

  def actively_tapped?(%__MODULE__{tap_expires_at: expires_at}) do
    DateTime.compare(DateTime.utc_now(), expires_at) == :lt
  end

  @doc """
  Tap (claim) the node for a character.
  """
  @spec tap(t(), integer()) :: t()
  def tap(%__MODULE__{} = node, character_id) do
    expires_at = DateTime.add(DateTime.utc_now(), @tap_duration_seconds, :second)

    %{node | tapped_by: character_id, tap_expires_at: expires_at}
  end

  @doc """
  Mark the node as harvested with a respawn timer.
  """
  @spec harvest(t(), integer()) :: t()
  def harvest(%__MODULE__{} = node, respawn_seconds) do
    respawn_at = DateTime.add(DateTime.utc_now(), respawn_seconds, :second)

    %{node | respawn_at: respawn_at, tapped_by: nil, tap_expires_at: nil}
  end

  @doc """
  Check if a character can harvest this node.
  """
  @spec can_harvest?(t(), integer()) :: boolean()
  def can_harvest?(%__MODULE__{tapped_by: nil}, _character_id), do: true

  def can_harvest?(%__MODULE__{tapped_by: tapper}, character_id) when tapper == character_id,
    do: true

  def can_harvest?(%__MODULE__{} = node, _character_id) do
    # Can harvest if tap has expired
    not actively_tapped?(node)
  end

  @doc """
  Clear respawn state (for respawned nodes).
  """
  @spec respawn(t()) :: t()
  def respawn(%__MODULE__{} = node) do
    %{node | respawn_at: nil}
  end
end
