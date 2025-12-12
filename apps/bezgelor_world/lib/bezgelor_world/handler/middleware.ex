defmodule BezgelorWorld.Handler.Middleware do
  @moduledoc """
  Middleware pipeline for world handlers.

  ## Overview

  Provides composable validation and pre-processing steps that are commonly
  needed across handlers. This eliminates duplicated validation code like
  "is player in world?", "is player alive?", etc.

  ## Usage

      alias BezgelorWorld.Handler.Middleware

      def handle(payload, state) do
        Middleware.run(state, [
          &Middleware.require_in_world/1,
          &Middleware.extract_entity/1,
          &Middleware.require_alive/1
        ], fn context ->
          # Handler logic - context is guaranteed to have in_world, entity, etc.
          process_action(packet, context)
        end)
      end

  ## Context

  The middleware pipeline builds up a context map containing:

  - `:state` - Original connection state
  - `:session` - Session data extracted from state
  - `:entity` - The player's entity (if extracted)
  - `:entity_guid` - The player's entity GUID
  - `:character_name` - The player's character name
  - `:target_guid` - The player's current target (if validated)

  ## Custom Middleware

  You can create custom middleware functions that match the signature:

      @spec my_middleware(context :: map()) :: {:ok, map()} | {:error, atom()}

  Return `{:ok, updated_context}` to continue the pipeline, or
  `{:error, reason}` to short-circuit and return the error.
  """

  require Logger

  @type context :: %{
          state: map(),
          session: map(),
          entity: map() | nil,
          entity_guid: non_neg_integer() | nil,
          character_name: String.t() | nil,
          target_guid: non_neg_integer() | nil
        }

  @type middleware_result :: {:ok, context()} | {:error, atom()}

  @doc """
  Run a handler function with middleware pipeline.

  ## Parameters

  - `state` - Connection state passed to the handler
  - `middlewares` - List of middleware functions to run in order
  - `handler_fn` - Function to execute if all middleware passes

  ## Returns

  Returns the result of `handler_fn` if all middleware passes,
  or `{:error, reason}` if any middleware fails.

  ## Example

      Middleware.run(state, [
        &Middleware.require_in_world/1,
        &Middleware.extract_entity/1,
        &Middleware.require_alive/1
      ], fn context ->
        # Safe to use context.entity here
        do_something(context.entity, context.session)
      end)
  """
  @spec run(map(), [function()], function()) :: any()
  def run(state, middlewares, handler_fn) do
    context = %{
      state: state,
      session: Map.get(state, :session_data, %{}),
      entity: nil,
      entity_guid: nil,
      character_name: nil,
      target_guid: nil
    }

    case run_middlewares(middlewares, context) do
      {:ok, context} ->
        handler_fn.(context)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp run_middlewares([], context), do: {:ok, context}

  defp run_middlewares([middleware | rest], context) do
    case middleware.(context) do
      {:ok, context} -> run_middlewares(rest, context)
      {:error, reason} -> {:error, reason}
    end
  end

  # ============================================================================
  # Standard Middleware Functions
  # ============================================================================

  @doc """
  Require player to be in world.

  Returns `{:error, :not_in_world}` if the player has not completed world entry.
  """
  @spec require_in_world(context()) :: middleware_result()
  def require_in_world(%{session: session} = context) do
    if session[:in_world] do
      {:ok, context}
    else
      Logger.warning("Action received before player entered world")
      {:error, :not_in_world}
    end
  end

  @doc """
  Extract entity data from session into context.

  Populates `:entity`, `:entity_guid`, and `:character_name` in the context.
  """
  @spec extract_entity(context()) :: middleware_result()
  def extract_entity(%{session: session} = context) do
    context = %{
      context
      | entity: session[:entity],
        entity_guid: session[:entity_guid],
        character_name: session[:character_name]
    }

    {:ok, context}
  end

  @doc """
  Require the player's entity to exist and be alive.

  Returns `{:error, :dead}` if the entity has no health.
  """
  @spec require_alive(context()) :: middleware_result()
  def require_alive(%{entity: nil}) do
    {:error, :no_entity}
  end

  def require_alive(%{entity: entity} = context) do
    if entity.health > 0 do
      {:ok, context}
    else
      {:error, :dead}
    end
  end

  @doc """
  Require the player to have a valid target.

  Populates `:target_guid` in the context.
  """
  @spec require_target(context()) :: middleware_result()
  def require_target(%{entity: nil}) do
    {:error, :no_entity}
  end

  def require_target(%{entity: entity} = context) do
    if entity[:target_guid] do
      {:ok, %{context | target_guid: entity.target_guid}}
    else
      {:error, :no_target}
    end
  end

  @doc """
  Require the player to not be in combat.

  Useful for actions that cannot be performed while fighting.
  """
  @spec require_not_in_combat(context()) :: middleware_result()
  def require_not_in_combat(%{session: session} = context) do
    if session[:in_combat] do
      {:error, :in_combat}
    else
      {:ok, context}
    end
  end

  @doc """
  Require the player to be in combat.

  Useful for combat-only actions.
  """
  @spec require_in_combat(context()) :: middleware_result()
  def require_in_combat(%{session: session} = context) do
    if session[:in_combat] do
      {:ok, context}
    else
      {:error, :not_in_combat}
    end
  end

  @doc """
  Log handler entry with character name.

  Returns a middleware function for the specific handler.

  ## Example

      Middleware.run(state, [
        Middleware.log_entry("ChatHandler"),
        &Middleware.require_in_world/1
      ], fn context -> ... end)
  """
  @spec log_entry(String.t()) :: (context() -> middleware_result())
  def log_entry(handler_name) do
    fn context ->
      name = context[:character_name] || "unknown"
      Logger.debug("#{handler_name}: processing for #{name}")
      {:ok, context}
    end
  end

  @doc """
  Extract a specific value from session data.

  Returns a middleware function that adds the value to context.

  ## Example

      Middleware.run(state, [
        Middleware.extract(:account_id),
        Middleware.extract(:character_id)
      ], fn context ->
        # context.account_id and context.character_id are available
      end)
  """
  @spec extract(atom()) :: (context() -> middleware_result())
  def extract(key) when is_atom(key) do
    fn %{session: session} = context ->
      value = session[key]
      {:ok, Map.put(context, key, value)}
    end
  end

  @doc """
  Require a specific session value to be present.

  ## Example

      Middleware.run(state, [
        Middleware.require(:guild_id, :not_in_guild)
      ], fn context -> ... end)
  """
  @spec require(atom(), atom()) :: (context() -> middleware_result())
  def require(key, error_reason) when is_atom(key) and is_atom(error_reason) do
    fn %{session: session} = context ->
      case session[key] do
        nil -> {:error, error_reason}
        value -> {:ok, Map.put(context, key, value)}
      end
    end
  end

  @doc """
  Validate that a condition is true.

  ## Example

      Middleware.run(state, [
        Middleware.validate(
          fn ctx -> ctx.session[:level] >= 10 end,
          :level_too_low
        )
      ], fn context -> ... end)
  """
  @spec validate((context() -> boolean()), atom()) :: (context() -> middleware_result())
  def validate(condition_fn, error_reason) when is_function(condition_fn, 1) do
    fn context ->
      if condition_fn.(context) do
        {:ok, context}
      else
        {:error, error_reason}
      end
    end
  end
end
