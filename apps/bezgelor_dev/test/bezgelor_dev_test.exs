defmodule BezgelorDevTest do
  # Not async due to Application.put_env modifications
  use ExUnit.Case, async: false

  setup do
    # Store original values
    original = %{
      mode: Application.get_env(:bezgelor_dev, :mode),
      interactive_mode: Application.get_env(:bezgelor_dev, :interactive_mode),
      capture_directory: Application.get_env(:bezgelor_dev, :capture_directory),
      packet_history_size: Application.get_env(:bezgelor_dev, :packet_history_size)
    }

    # Reset to defaults for each test
    Application.put_env(:bezgelor_dev, :mode, :disabled)
    Application.delete_env(:bezgelor_dev, :interactive_mode)
    Application.delete_env(:bezgelor_dev, :capture_directory)
    Application.delete_env(:bezgelor_dev, :packet_history_size)

    on_exit(fn ->
      # Restore original values or delete if nil
      restore_or_delete(:bezgelor_dev, :mode, original.mode)
      restore_or_delete(:bezgelor_dev, :interactive_mode, original.interactive_mode)
      restore_or_delete(:bezgelor_dev, :capture_directory, original.capture_directory)
      restore_or_delete(:bezgelor_dev, :packet_history_size, original.packet_history_size)
    end)

    :ok
  end

  defp restore_or_delete(app, key, nil), do: Application.delete_env(app, key)
  defp restore_or_delete(app, key, value), do: Application.put_env(app, key, value)

  describe "mode/0" do
    test "returns :disabled by default" do
      assert BezgelorDev.mode() == :disabled
    end

    test "returns configured mode" do
      Application.put_env(:bezgelor_dev, :mode, :logging)
      assert BezgelorDev.mode() == :logging

      Application.put_env(:bezgelor_dev, :mode, :interactive)
      assert BezgelorDev.mode() == :interactive
    end
  end

  describe "enabled?/0" do
    test "returns false when mode is :disabled" do
      Application.put_env(:bezgelor_dev, :mode, :disabled)
      refute BezgelorDev.enabled?()
    end

    test "returns true when mode is :logging" do
      Application.put_env(:bezgelor_dev, :mode, :logging)
      assert BezgelorDev.enabled?()
    end

    test "returns true when mode is :interactive" do
      Application.put_env(:bezgelor_dev, :mode, :interactive)
      assert BezgelorDev.enabled?()
    end
  end

  describe "interactive_mode/0" do
    test "returns :log_only by default" do
      assert BezgelorDev.interactive_mode() == :log_only
    end
  end

  describe "llm_enabled?/0" do
    test "returns false when mode is :disabled" do
      Application.put_env(:bezgelor_dev, :mode, :disabled)
      refute BezgelorDev.llm_enabled?()
    end

    test "returns false when mode is :interactive but interactive_mode is :log_only" do
      Application.put_env(:bezgelor_dev, :mode, :interactive)
      Application.put_env(:bezgelor_dev, :interactive_mode, :log_only)
      refute BezgelorDev.llm_enabled?()
    end

    test "returns true when mode is :interactive and interactive_mode is :llm_assisted" do
      Application.put_env(:bezgelor_dev, :mode, :interactive)
      Application.put_env(:bezgelor_dev, :interactive_mode, :llm_assisted)
      assert BezgelorDev.llm_enabled?()
    end
  end

  describe "capture_directory/0" do
    test "returns default capture directory" do
      assert BezgelorDev.capture_directory() == "priv/dev_captures"
    end

    test "returns configured capture directory" do
      Application.put_env(:bezgelor_dev, :capture_directory, "/custom/path")
      assert BezgelorDev.capture_directory() == "/custom/path"
    end
  end

  describe "packet_history_size/0" do
    test "returns default packet history size" do
      assert BezgelorDev.packet_history_size() == 20
    end

    test "returns configured packet history size" do
      Application.put_env(:bezgelor_dev, :packet_history_size, 50)
      assert BezgelorDev.packet_history_size() == 50
    end
  end
end
