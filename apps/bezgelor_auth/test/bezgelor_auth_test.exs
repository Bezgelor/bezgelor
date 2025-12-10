defmodule BezgelorAuthTest do
  use ExUnit.Case
  doctest BezgelorAuth

  test "returns configured port" do
    # Default port is 6600
    assert BezgelorAuth.port() == 6600
  end
end
