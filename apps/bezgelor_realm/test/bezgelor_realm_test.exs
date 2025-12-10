defmodule BezgelorRealmTest do
  use ExUnit.Case

  test "returns configured port" do
    # Default port is 23115
    assert BezgelorRealm.port() == 23115
  end
end
