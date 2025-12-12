defmodule BezgelorDev.Hooks do
  @moduledoc """
  Compile-time hooks for development capture.

  These macros expand to no-ops when dev mode is disabled at compile time,
  ensuring zero runtime overhead in production. The mode is determined by
  the `:bezgelor_dev` application config at compile time.

  ## Usage

  In `BezgelorProtocol.Connection`:

      require BezgelorDev.Hooks
      alias BezgelorDev.Hooks

      # In handle_packet/3:
      Hooks.on_unknown_opcode(opcode, payload, state)

      # In dispatch_to_handler/3:
      Hooks.on_unhandled_opcode(opcode_atom, payload, state)

      # After sending packets:
      Hooks.track_packet(:outbound, opcode, payload, state)

  ## Compile-time Behavior

  When `config :bezgelor_dev, mode: :disabled`, all hooks expand to `:ok`
  at compile time, resulting in zero runtime cost. No function calls,
  no condition checks - just a literal `:ok` in the compiled code.
  """

  # Read the mode at compile time - this is evaluated when the module is compiled
  @dev_mode_enabled Application.compile_env(:bezgelor_dev, :mode, :disabled) != :disabled

  @doc """
  Hook called when an unknown opcode (not in Opcode module) is received.

  Compiles to `:ok` when dev mode is disabled.
  """
  defmacro on_unknown_opcode(opcode_int, payload, state) do
    if @dev_mode_enabled do
      quote do
        BezgelorDev.DevCapture.capture_unknown_opcode(
          unquote(opcode_int),
          unquote(payload),
          unquote(state)
        )
      end
    else
      quote do: :ok
    end
  end

  @doc """
  Hook called when a known opcode has no registered handler.

  Compiles to `:ok` when dev mode is disabled.
  """
  defmacro on_unhandled_opcode(opcode_atom, payload, state) do
    if @dev_mode_enabled do
      quote do
        BezgelorDev.DevCapture.capture_unhandled_opcode(
          unquote(opcode_atom),
          unquote(payload),
          unquote(state)
        )
      end
    else
      quote do: :ok
    end
  end

  @doc """
  Hook called when a handler returns an error.

  Compiles to `:ok` when dev mode is disabled.
  """
  defmacro on_handler_error(opcode_atom, payload, error, state) do
    if @dev_mode_enabled do
      quote do
        BezgelorDev.DevCapture.capture_handler_error(
          unquote(opcode_atom),
          unquote(payload),
          unquote(error),
          unquote(state)
        )
      end
    else
      quote do: :ok
    end
  end

  @doc """
  Hook to track packets for context history.

  Call this for both inbound and outbound packets to maintain
  a history of recent packets for context when capturing events.

  Compiles to `:ok` when dev mode is disabled.
  """
  defmacro track_packet(direction, opcode, payload, state) do
    if @dev_mode_enabled do
      quote do
        BezgelorDev.DevCapture.track_packet(
          unquote(direction),
          unquote(opcode),
          unquote(payload),
          unquote(state)
        )
      end
    else
      quote do: :ok
    end
  end

  @doc """
  Returns true if dev mode is enabled at compile time.
  """
  @spec dev_mode_enabled?() :: boolean()
  def dev_mode_enabled?, do: @dev_mode_enabled
end
