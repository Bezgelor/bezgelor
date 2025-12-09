defmodule BezgelorCrypto.RandomTest do
  use ExUnit.Case, async: true

  alias BezgelorCrypto.Random

  describe "bytes/1" do
    test "generates bytes of requested length" do
      bytes = Random.bytes(16)
      assert byte_size(bytes) == 16
    end

    test "generates different bytes each call" do
      bytes1 = Random.bytes(16)
      bytes2 = Random.bytes(16)
      assert bytes1 != bytes2
    end
  end

  describe "uuid/0" do
    test "generates valid UUID format" do
      uuid = Random.uuid()
      # UUID format: 8-4-4-4-12 hex chars
      assert String.match?(uuid, ~r/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/)
    end
  end

  describe "big_integer/1" do
    test "generates positive integer of specified byte size" do
      int = Random.big_integer(16)
      assert is_integer(int)
      assert int > 0
    end
  end
end
