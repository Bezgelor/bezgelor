defmodule BezgelorProtocolTest do
  use ExUnit.Case, async: true
  doctest BezgelorProtocol

  describe "BezgelorProtocol" do
    test "module exists and provides version" do
      assert BezgelorProtocol.version() == "0.1.0"
    end
  end
end
