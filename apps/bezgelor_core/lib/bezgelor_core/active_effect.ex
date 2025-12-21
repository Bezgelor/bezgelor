defmodule BezgelorCore.ActiveEffect do
  @moduledoc """
  Active effect state management.

  ## Overview

  This module manages the state of active buffs and debuffs on an entity.
  State is a map from buff_id to effect data including expiration time.

  ## State Structure

      %{
        buff_id => %{
          buff: %BuffDebuff{},
          caster_guid: integer,
          expires_at: integer  # monotonic time in ms
        }
      }

  ## Usage

      iex> state = ActiveEffect.new()
      iex> buff = BuffDebuff.new(%{id: 1, spell_id: 4, buff_type: :absorb, amount: 100, duration: 10_000})
      iex> state = ActiveEffect.apply(state, buff, caster_guid, now_ms)
      iex> ActiveEffect.active?(state, 1, now_ms + 5000)
      true
  """

  alias BezgelorCore.BuffDebuff

  @type effect_data :: %{
          buff: BuffDebuff.t(),
          caster_guid: non_neg_integer(),
          expires_at: integer()
        }

  @type state :: %{non_neg_integer() => effect_data()}

  @doc """
  Create a new empty active effect state.
  """
  @spec new() :: state()
  def new, do: %{}

  @doc """
  Apply a buff/debuff to the state.

  If a buff with the same ID already exists, it is replaced (refreshed).
  """
  @spec apply(state(), BuffDebuff.t(), non_neg_integer(), integer()) :: state()
  def apply(state, %BuffDebuff{} = buff, caster_guid, now_ms) do
    expires_at = now_ms + buff.duration

    effect_data = %{
      buff: buff,
      caster_guid: caster_guid,
      expires_at: expires_at
    }

    Map.put(state, buff.id, effect_data)
  end

  @doc """
  Remove a buff/debuff from the state.
  """
  @spec remove(state(), non_neg_integer()) :: state()
  def remove(state, buff_id) do
    Map.delete(state, buff_id)
  end

  @doc """
  Check if a buff is active (exists and not expired).
  """
  @spec active?(state(), non_neg_integer(), integer()) :: boolean()
  def active?(state, buff_id, now_ms) do
    case Map.get(state, buff_id) do
      nil -> false
      %{expires_at: expires_at} -> expires_at > now_ms
    end
  end

  @doc """
  Get remaining duration of a buff in milliseconds.
  """
  @spec remaining(state(), non_neg_integer(), integer()) :: non_neg_integer()
  def remaining(state, buff_id, now_ms) do
    case Map.get(state, buff_id) do
      nil -> 0
      %{expires_at: expires_at} -> max(0, expires_at - now_ms)
    end
  end

  @doc """
  Remove all expired effects from state.
  """
  @spec cleanup(state(), integer()) :: state()
  def cleanup(state, now_ms) do
    Map.filter(state, fn {_id, %{expires_at: expires_at}} ->
      expires_at > now_ms
    end)
  end

  @doc """
  Get total stat modifier for a given stat from all active effects.
  """
  @spec get_stat_modifier(state(), BuffDebuff.stat(), integer()) :: integer()
  def get_stat_modifier(state, stat, now_ms) do
    state
    |> Enum.filter(fn {_id, %{buff: buff, expires_at: expires_at}} ->
      expires_at > now_ms and
        buff.buff_type == :stat_modifier and
        buff.stat == stat
    end)
    |> Enum.reduce(0, fn {_id, %{buff: buff}}, acc ->
      acc + buff.amount
    end)
  end

  @doc """
  Get total remaining absorb amount from all active absorb effects.
  """
  @spec get_absorb_remaining(state(), integer()) :: non_neg_integer()
  def get_absorb_remaining(state, now_ms) do
    state
    |> Enum.filter(fn {_id, %{buff: buff, expires_at: expires_at}} ->
      expires_at > now_ms and buff.buff_type == :absorb
    end)
    |> Enum.reduce(0, fn {_id, %{buff: buff}}, acc ->
      acc + buff.amount
    end)
  end

  @doc """
  Consume absorb shields to reduce incoming damage.

  Returns `{updated_state, absorbed_amount, remaining_damage}`.
  Consumes from oldest absorb effects first (by buff_id order).
  """
  @spec consume_absorb(state(), non_neg_integer(), integer()) ::
          {state(), non_neg_integer(), non_neg_integer()}
  def consume_absorb(state, damage, now_ms) when damage > 0 do
    # Get active absorb buffs sorted by id (oldest first)
    absorb_buffs =
      state
      |> Enum.filter(fn {_id, %{buff: buff, expires_at: expires_at}} ->
        expires_at > now_ms and buff.buff_type == :absorb
      end)
      |> Enum.sort_by(fn {id, _} -> id end)

    consume_absorb_loop(state, absorb_buffs, damage, 0)
  end

  def consume_absorb(state, 0, _now_ms), do: {state, 0, 0}

  defp consume_absorb_loop(state, [], remaining_damage, total_absorbed) do
    {state, total_absorbed, remaining_damage}
  end

  defp consume_absorb_loop(state, _absorb_buffs, 0, total_absorbed) do
    {state, total_absorbed, 0}
  end

  defp consume_absorb_loop(
         state,
         [{buff_id, effect_data} | rest],
         remaining_damage,
         total_absorbed
       ) do
    absorb_amount = effect_data.buff.amount

    cond do
      absorb_amount > remaining_damage ->
        # Partial absorb - reduce buff amount
        new_amount = absorb_amount - remaining_damage
        updated_buff = %{effect_data.buff | amount: new_amount}
        updated_data = %{effect_data | buff: updated_buff}
        state = Map.put(state, buff_id, updated_data)
        {state, total_absorbed + remaining_damage, 0}

      absorb_amount == remaining_damage ->
        # Exact absorb - remove buff
        state = Map.delete(state, buff_id)
        {state, total_absorbed + absorb_amount, 0}

      true ->
        # Buff fully consumed - remove and continue
        state = Map.delete(state, buff_id)
        new_remaining = remaining_damage - absorb_amount
        consume_absorb_loop(state, rest, new_remaining, total_absorbed + absorb_amount)
    end
  end

  @doc """
  List all active effects with remaining duration.
  """
  @spec list_active(state(), integer()) :: [effect_data()]
  def list_active(state, now_ms) do
    state
    |> Enum.filter(fn {_id, %{expires_at: expires_at}} -> expires_at > now_ms end)
    |> Enum.map(fn {_id, data} -> data end)
  end
end
