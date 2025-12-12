defmodule BezgelorDev do
  @moduledoc """
  Development capture system for reverse engineering WildStar protocol.

  This module provides infrastructure for capturing unknown/unhandled packets
  during gameplay, collecting rich context, and optionally using Claude API
  to assist with reverse engineering.

  ## Modes

  - `:disabled` - No capture, zero overhead (default in production)
  - `:logging` - Capture packets to log files for later analysis
  - `:interactive` - Real-time prompts during gameplay

  ## Interactive Sub-modes

  When mode is `:interactive`:
  - `:log_only` - Prompt for context, save to files
  - `:llm_assisted` - Prompt for context, analyze with LLM API

  ## Configuration

      # config/dev.exs
      config :bezgelor_dev,
        mode: :interactive,
        interactive_mode: :llm_assisted,
        claude_api_key: System.get_env("ANTHROPIC_API_KEY"),
        claude_model: "claude-sonnet-4-20250514",
        packet_history_size: 20,
        capture_directory: "priv/dev_captures"

  ## Usage

  The system integrates with `BezgelorProtocol.Connection` via compile-time
  macros that expand to no-ops when disabled, ensuring zero runtime overhead
  in production.
  """

  @type mode :: :disabled | :logging | :interactive
  @type interactive_mode :: :log_only | :llm_assisted

  @doc """
  Returns the current development capture mode.

  ## Examples

      iex> BezgelorDev.mode()
      :disabled

  """
  @spec mode() :: mode()
  def mode do
    Application.get_env(:bezgelor_dev, :mode, :disabled)
  end

  @doc """
  Returns the interactive sub-mode when mode is `:interactive`.

  ## Examples

      iex> BezgelorDev.interactive_mode()
      :log_only

  """
  @spec interactive_mode() :: interactive_mode()
  def interactive_mode do
    Application.get_env(:bezgelor_dev, :interactive_mode, :log_only)
  end

  @doc """
  Returns true if development capture is enabled (not :disabled).
  """
  @spec enabled?() :: boolean()
  def enabled? do
    mode() != :disabled
  end

  @doc """
  Returns true if LLM API integration is enabled.
  """
  @spec llm_enabled?() :: boolean()
  def llm_enabled? do
    mode() == :interactive and interactive_mode() == :llm_assisted
  end

  @doc """
  Returns the capture directory path.
  """
  @spec capture_directory() :: String.t()
  def capture_directory do
    Application.get_env(:bezgelor_dev, :capture_directory, "priv/dev_captures")
  end

  @doc """
  Returns the packet history size for context tracking.
  """
  @spec packet_history_size() :: pos_integer()
  def packet_history_size do
    Application.get_env(:bezgelor_dev, :packet_history_size, 20)
  end
end
