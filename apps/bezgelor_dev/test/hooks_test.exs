defmodule BezgelorDev.HooksTest do
  use ExUnit.Case, async: true

  alias BezgelorDev.Hooks

  describe "dev_mode_enabled?/0" do
    test "returns boolean based on compile-time config" do
      # Since this is determined at compile time, we can only test the function exists
      # and returns a boolean. The actual value depends on the compile-time config.
      result = Hooks.dev_mode_enabled?()
      assert is_boolean(result)
    end
  end

  # Note: The macros (on_unknown_opcode, on_unhandled_opcode, on_handler_error, track_packet)
  # are compile-time constructs. Testing them would require:
  # 1. A separate test module compiled with dev mode enabled
  # 2. Mocking the DevCapture GenServer
  #
  # For now, we verify the module compiles and the helper function works.
  # Full integration tests would be in a separate test file that requires DevCapture to be running.

  describe "macro compilation" do
    test "module compiles with hook macros available" do
      # If we got here, the module compiled successfully
      assert Code.ensure_loaded?(BezgelorDev.Hooks)

      # Verify the macros are defined
      exports = BezgelorDev.Hooks.__info__(:macros)
      assert {:on_unknown_opcode, 3} in exports
      assert {:on_unhandled_opcode, 3} in exports
      assert {:on_handler_error, 4} in exports
      assert {:track_packet, 4} in exports
    end
  end
end
