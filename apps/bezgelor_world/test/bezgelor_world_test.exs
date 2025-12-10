defmodule BezgelorWorldTest do
  use ExUnit.Case
  doctest BezgelorWorld

  test "greets the world" do
    assert BezgelorWorld.hello() == :world
  end
end
