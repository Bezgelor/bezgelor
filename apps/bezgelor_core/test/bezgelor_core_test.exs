defmodule BezgelorCoreTest do
  use ExUnit.Case
  doctest BezgelorCore

  test "greets the world" do
    assert BezgelorCore.hello() == :world
  end
end
