defmodule BezgelorCore.ConfigTest do
  use ExUnit.Case, async: true

  alias BezgelorCore.Config

  describe "get/2" do
    test "retrieves application config value" do
      # Application.put_env is used in test setup
      Application.put_env(:bezgelor_core, :test_key, "test_value")
      assert Config.get(:bezgelor_core, :test_key) == "test_value"
    end

    test "returns default when key missing" do
      assert Config.get(:bezgelor_core, :missing_key, "default") == "default"
    end
  end

  describe "get!/2" do
    test "raises when key is missing" do
      assert_raise KeyError, fn ->
        Config.get!(:bezgelor_core, :definitely_missing)
      end
    end
  end
end
