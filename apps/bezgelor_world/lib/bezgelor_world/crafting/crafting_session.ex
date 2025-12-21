defmodule BezgelorWorld.Crafting.CraftingSession do
  @moduledoc """
  In-memory crafting session state.

  Tracks the current state of an active craft including cursor position,
  additives used, and overcharge level. Sessions are stored in player
  GenServer state and are lost on disconnect (matching original behavior).
  """

  alias BezgelorWorld.Crafting.CoordinateSystem

  @max_overcharge 3

  defstruct [
    :schematic_id,
    :started_at,
    cursor_x: 0.0,
    cursor_y: 0.0,
    additives_used: [],
    overcharge_level: 0
  ]

  @type t :: %__MODULE__{
          schematic_id: integer(),
          cursor_x: float(),
          cursor_y: float(),
          additives_used: [additive_record()],
          overcharge_level: non_neg_integer(),
          started_at: DateTime.t()
        }

  @type additive_record :: %{
          item_id: integer(),
          quantity: integer(),
          vector_x: float(),
          vector_y: float()
        }

  @doc """
  Create a new crafting session for a schematic.
  """
  @spec new(integer()) :: t()
  def new(schematic_id) do
    %__MODULE__{
      schematic_id: schematic_id,
      started_at: DateTime.utc_now()
    }
  end

  @doc """
  Add an additive to the session, updating cursor position.
  """
  @spec add_additive(t(), additive_record()) :: t()
  def add_additive(%__MODULE__{} = session, additive) do
    {new_x, new_y} =
      CoordinateSystem.apply_additive(
        {session.cursor_x, session.cursor_y},
        additive,
        session.overcharge_level
      )

    %{
      session
      | cursor_x: new_x,
        cursor_y: new_y,
        additives_used: session.additives_used ++ [additive]
    }
  end

  @doc """
  Set the overcharge level (clamped to 0-3).
  """
  @spec set_overcharge(t(), integer()) :: t()
  def set_overcharge(%__MODULE__{} = session, level) do
    clamped = level |> max(0) |> min(@max_overcharge)
    %{session | overcharge_level: clamped}
  end

  @doc """
  Get current cursor position as tuple.
  """
  @spec get_cursor(t()) :: {float(), float()}
  def get_cursor(%__MODULE__{cursor_x: x, cursor_y: y}), do: {x, y}

  @doc """
  Get the total material cost (additives consumed).
  """
  @spec get_material_cost(t()) :: [{integer(), integer()}]
  def get_material_cost(%__MODULE__{additives_used: additives}) do
    additives
    |> Enum.group_by(& &1.item_id)
    |> Enum.map(fn {item_id, items} ->
      total = Enum.sum(Enum.map(items, & &1.quantity))
      {item_id, total}
    end)
  end
end
