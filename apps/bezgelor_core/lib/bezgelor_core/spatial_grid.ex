defmodule BezgelorCore.SpatialGrid do
  @moduledoc """
  Grid-based spatial index for O(1) cell lookups + O(k) neighbor iteration.

  Divides the world into cells of fixed size. Range queries only check
  entities in relevant cells rather than all entities.

  ## Performance

  - Insert: O(1)
  - Remove: O(1)
  - Update position: O(1)
  - Range query: O(k) where k = entities in nearby cells (typically < 50)

  Compare to naive iteration which is O(n) for all entities.

  ## Example

      grid = SpatialGrid.new(50.0)
        |> SpatialGrid.insert(player_guid, {100.0, 50.0, 0.0})
        |> SpatialGrid.insert(creature_guid, {120.0, 50.0, 0.0})

      # Find all entities within 30 units of position
      nearby = SpatialGrid.entities_in_range(grid, {110.0, 50.0, 0.0}, 30.0)
  """

  @default_cell_size 50.0

  @type position :: {float(), float(), float()}
  @type cell :: {integer(), integer(), integer()}
  @type guid :: non_neg_integer()

  @type t :: %__MODULE__{
          cells: %{cell() => MapSet.t(guid())},
          entity_positions: %{guid() => position()},
          cell_size: float()
        }

  defstruct cells: %{}, entity_positions: %{}, cell_size: @default_cell_size

  @doc """
  Create a new spatial grid with the given cell size.

  Smaller cell sizes provide more precise queries but use more memory.
  Larger cell sizes use less memory but check more entities per query.

  Recommended: 50.0 for outdoor zones, 25.0 for dungeons/instances.
  """
  @spec new(float()) :: t()
  def new(cell_size \\ @default_cell_size) when is_number(cell_size) and cell_size > 0 do
    %__MODULE__{cell_size: cell_size}
  end

  @doc """
  Insert an entity at a position.

  If the entity already exists, it will be updated to the new position.
  """
  @spec insert(t(), guid(), position()) :: t()
  def insert(%__MODULE__{} = grid, guid, {x, y, z} = position)
      when is_integer(guid) and is_number(x) and is_number(y) and is_number(z) do
    # Remove from old position if exists
    grid = remove(grid, guid)

    cell = position_to_cell(position, grid.cell_size)

    cells = Map.update(grid.cells, cell, MapSet.new([guid]), &MapSet.put(&1, guid))
    positions = Map.put(grid.entity_positions, guid, position)

    %{grid | cells: cells, entity_positions: positions}
  end

  @doc """
  Remove an entity from the grid.

  No-op if entity doesn't exist.
  """
  @spec remove(t(), guid()) :: t()
  def remove(%__MODULE__{} = grid, guid) when is_integer(guid) do
    case Map.get(grid.entity_positions, guid) do
      nil ->
        grid

      position ->
        cell = position_to_cell(position, grid.cell_size)

        cells =
          case Map.get(grid.cells, cell) do
            nil ->
              grid.cells

            cell_entities ->
              new_entities = MapSet.delete(cell_entities, guid)

              if MapSet.size(new_entities) == 0 do
                Map.delete(grid.cells, cell)
              else
                Map.put(grid.cells, cell, new_entities)
              end
          end

        positions = Map.delete(grid.entity_positions, guid)

        %{grid | cells: cells, entity_positions: positions}
    end
  end

  @doc """
  Update an entity's position.

  More efficient than remove + insert when entity already exists.
  """
  @spec update(t(), guid(), position()) :: t()
  def update(%__MODULE__{} = grid, guid, {x, y, z} = new_position)
      when is_integer(guid) and is_number(x) and is_number(y) and is_number(z) do
    case Map.get(grid.entity_positions, guid) do
      nil ->
        # Entity doesn't exist, just insert
        insert(grid, guid, new_position)

      old_position ->
        old_cell = position_to_cell(old_position, grid.cell_size)
        new_cell = position_to_cell(new_position, grid.cell_size)

        if old_cell == new_cell do
          # Same cell, just update position
          %{grid | entity_positions: Map.put(grid.entity_positions, guid, new_position)}
        else
          # Different cell, need to move between cells
          grid
          |> remove(guid)
          |> insert(guid, new_position)
        end
    end
  end

  @doc """
  Get all entity GUIDs within range of a position.

  Returns a list of GUIDs. The caller is responsible for looking up
  the actual entity data from their storage.
  """
  @spec entities_in_range(t(), position(), float()) :: [guid()]
  def entities_in_range(%__MODULE__{} = grid, {x, y, z} = position, radius)
      when is_number(x) and is_number(y) and is_number(z) and is_number(radius) and radius >= 0 do
    # Calculate which cells to check
    cells_to_check = cells_in_range(position, radius, grid.cell_size)
    radius_sq = radius * radius

    # Gather entities from relevant cells and filter by exact distance
    cells_to_check
    |> Enum.flat_map(fn cell ->
      Map.get(grid.cells, cell, MapSet.new()) |> MapSet.to_list()
    end)
    |> Enum.filter(fn guid ->
      case Map.get(grid.entity_positions, guid) do
        nil ->
          false

        {ex, ey, ez} ->
          dx = ex - x
          dy = ey - y
          dz = ez - z
          dx * dx + dy * dy + dz * dz <= radius_sq
      end
    end)
  end

  @doc """
  Get the position of an entity.

  Returns nil if entity not found.
  """
  @spec get_position(t(), guid()) :: position() | nil
  def get_position(%__MODULE__{} = grid, guid) when is_integer(guid) do
    Map.get(grid.entity_positions, guid)
  end

  @doc """
  Check if an entity exists in the grid.
  """
  @spec has_entity?(t(), guid()) :: boolean()
  def has_entity?(%__MODULE__{} = grid, guid) when is_integer(guid) do
    Map.has_key?(grid.entity_positions, guid)
  end

  @doc """
  Get the total number of entities in the grid.
  """
  @spec count(t()) :: non_neg_integer()
  def count(%__MODULE__{} = grid) do
    map_size(grid.entity_positions)
  end

  @doc """
  Get all entity GUIDs in the grid.
  """
  @spec all_guids(t()) :: [guid()]
  def all_guids(%__MODULE__{} = grid) do
    Map.keys(grid.entity_positions)
  end

  @doc """
  Get the cell for a given position.

  Useful for debugging or grouping entities.
  """
  @spec get_cell(t(), position()) :: cell()
  def get_cell(%__MODULE__{} = grid, position) do
    position_to_cell(position, grid.cell_size)
  end

  @doc """
  Get all entities in a specific cell.
  """
  @spec entities_in_cell(t(), cell()) :: [guid()]
  def entities_in_cell(%__MODULE__{} = grid, cell) do
    Map.get(grid.cells, cell, MapSet.new()) |> MapSet.to_list()
  end

  # Private functions

  defp position_to_cell({x, y, z}, cell_size) do
    {floor(x / cell_size), floor(y / cell_size), floor(z / cell_size)}
  end

  defp cells_in_range({x, y, z}, radius, cell_size) do
    cells_radius = ceil(radius / cell_size)
    {cx, cy, cz} = position_to_cell({x, y, z}, cell_size)

    for dx <- -cells_radius..cells_radius,
        dy <- -cells_radius..cells_radius,
        dz <- -cells_radius..cells_radius do
      {cx + dx, cy + dy, cz + dz}
    end
  end
end
