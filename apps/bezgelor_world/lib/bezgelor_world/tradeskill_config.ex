defmodule BezgelorWorld.TradeskillConfig do
  @moduledoc """
  Access tradeskill configuration values.
  """

  @doc """
  Get a tradeskill config value.
  """
  @spec get(atom()) :: term()
  def get(key) do
    config = Application.get_env(:bezgelor_world, :tradeskills, [])
    Keyword.get(config, key)
  end

  @doc """
  Get max crafting professions allowed (0 = unlimited).
  """
  @spec max_crafting_professions() :: non_neg_integer()
  def max_crafting_professions, do: get(:max_crafting_professions) || 2

  @doc """
  Get max gathering professions allowed (0 = unlimited).
  """
  @spec max_gathering_professions() :: non_neg_integer()
  def max_gathering_professions, do: get(:max_gathering_professions) || 3

  @doc """
  Whether to preserve progress when swapping professions.
  """
  @spec preserve_progress_on_swap?() :: boolean()
  def preserve_progress_on_swap?, do: get(:preserve_progress_on_swap) || false

  @doc """
  Discovery scope - :character or :account.
  """
  @spec discovery_scope() :: :character | :account
  def discovery_scope, do: get(:discovery_scope) || :character

  @doc """
  Node competition mode - :first_tap, :shared, or :instanced.
  """
  @spec node_competition() :: :first_tap | :shared | :instanced
  def node_competition, do: get(:node_competition) || :first_tap

  @doc """
  Respec policy - :free, :gold_cost, :item_required, or :disabled.
  """
  @spec respec_policy() :: :free | :gold_cost | :item_required | :disabled
  def respec_policy, do: get(:respec_policy) || :gold_cost

  @doc """
  Gold cost for respec (in copper).
  """
  @spec respec_gold_cost() :: non_neg_integer()
  def respec_gold_cost, do: get(:respec_gold_cost) || 10_00

  @doc """
  Station mode - :strict, :universal, or :housing_bypass.
  """
  @spec station_mode() :: :strict | :universal | :housing_bypass
  def station_mode, do: get(:station_mode) || :strict
end
