defmodule BezgelorDbTest do
  use ExUnit.Case
  doctest BezgelorDb

  test "greets the world" do
    assert BezgelorDb.hello() == :world
  end
end
