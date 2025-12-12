defmodule BezgelorWorld.PvP.Objectives.WalatikiMask do
  @moduledoc """
  Walatiki Temple mask capture mechanics.

  The mask spawns in the center of the map. Players can pick it up
  and carry it to their capture point to score. If the carrier dies,
  the mask drops and can be picked up by either faction.
  """

  @mask_return_time_ms 10_000

  defstruct [
    :id,
    :position,
    :state,
    :carrier_guid,
    :carrier_faction,
    :dropped_at,
    :drop_position
  ]

  @type mask_state :: :spawned | :carried | :dropped | :returning
  @type faction :: :exile | :dominion

  @type t :: %__MODULE__{
          id: non_neg_integer(),
          position: {float(), float(), float()},
          state: mask_state(),
          carrier_guid: non_neg_integer() | nil,
          carrier_faction: faction() | nil,
          dropped_at: integer() | nil,
          drop_position: {float(), float(), float()} | nil
        }

  @doc """
  Creates a new mask at the given spawn position.
  """
  @spec new(non_neg_integer(), {float(), float(), float()}) :: t()
  def new(id, position) do
    %__MODULE__{
      id: id,
      position: position,
      state: :spawned,
      carrier_guid: nil,
      carrier_faction: nil,
      dropped_at: nil,
      drop_position: nil
    }
  end

  @doc """
  Player picks up the mask.

  Returns:
  - `{:ok, mask}` when successfully picked up
  - `{:returned, mask}` when same faction returns a dropped mask
  - `{:error, reason}` when pickup fails
  """
  @spec pickup(t(), non_neg_integer(), faction()) ::
          {:ok, t()} | {:returned, t()} | {:error, atom()}
  def pickup(mask, player_guid, player_faction) do
    case mask.state do
      :spawned ->
        {:ok,
         %{
           mask
           | state: :carried,
             carrier_guid: player_guid,
             carrier_faction: player_faction
         }}

      :dropped ->
        if mask.carrier_faction == player_faction do
          # Own faction picks up dropped mask - return it
          {:returned, %{mask | state: :returning}}
        else
          # Enemy picks up dropped mask - they carry it now
          {:ok,
           %{
             mask
             | state: :carried,
               carrier_guid: player_guid,
               carrier_faction: player_faction,
               dropped_at: nil,
               drop_position: nil
           }}
        end

      _ ->
        {:error, :mask_not_available}
    end
  end

  @doc """
  Carrier reaches their capture point - score!
  """
  @spec capture(t(), faction()) :: {:captured, t()} | {:error, atom()}
  def capture(mask, capture_point_faction) do
    if mask.state == :carried and mask.carrier_faction == capture_point_faction do
      {:captured,
       %{
         mask
         | state: :returning,
           carrier_guid: nil,
           carrier_faction: nil
       }}
    else
      {:error, :invalid_capture}
    end
  end

  @doc """
  Carrier dies or disconnects.
  """
  @spec drop(t(), {float(), float(), float()}) :: {:ok, t()} | {:error, atom()}
  def drop(mask, position) do
    if mask.state == :carried do
      {:ok,
       %{
         mask
         | state: :dropped,
           drop_position: position,
           dropped_at: System.monotonic_time(:millisecond)
       }}
    else
      {:error, :not_carried}
    end
  end

  @doc """
  Check if dropped mask should return to center.
  """
  @spec check_return(t()) :: {:return, t()} | {:wait, t()} | {:ok, t()}
  def check_return(mask) do
    if mask.state == :dropped do
      elapsed = System.monotonic_time(:millisecond) - mask.dropped_at

      if elapsed >= @mask_return_time_ms do
        {:return, %{mask | state: :returning}}
      else
        {:wait, mask}
      end
    else
      {:ok, mask}
    end
  end

  @doc """
  Reset mask to spawned state at center position.
  """
  @spec respawn(t()) :: t()
  def respawn(mask) do
    %{
      mask
      | state: :spawned,
        carrier_guid: nil,
        carrier_faction: nil,
        dropped_at: nil,
        drop_position: nil
    }
  end

  @doc """
  Returns true if the mask is currently being carried.
  """
  @spec carried?(t()) :: boolean()
  def carried?(mask), do: mask.state == :carried

  @doc """
  Returns the return time in milliseconds.
  """
  @spec return_time_ms() :: non_neg_integer()
  def return_time_ms, do: @mask_return_time_ms
end
