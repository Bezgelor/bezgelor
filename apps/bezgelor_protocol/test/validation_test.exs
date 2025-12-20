defmodule BezgelorProtocol.ValidationTest do
  use ExUnit.Case, async: true

  alias BezgelorProtocol.Validation

  # Note: OTP 28+ prevents NaN/Infinity creation at the VM level.
  # Binary pattern matches fail when attempting to decode NaN/Infinity bytes.
  # This provides built-in protection against these malicious values.
  # The is_nan_or_inf/1 function remains for backward compatibility with older OTP.

  describe "validate_position/1" do
    test "accepts valid position" do
      assert :ok = Validation.validate_position({100.0, 50.0, 200.0})
      assert :ok = Validation.validate_position({0.0, 0.0, 0.0})
      assert :ok = Validation.validate_position({-500.5, 1000.0, -2000.0})
    end

    test "accepts integer components" do
      assert :ok = Validation.validate_position({100, 50, 200})
    end

    test "accepts boundary positions" do
      # Positions at the edge of valid bounds
      assert :ok = Validation.validate_position({100_000.0, 0.0, 0.0})
      assert :ok = Validation.validate_position({0.0, -100_000.0, 0.0})
    end

    test "rejects position out of bounds" do
      assert {:error, :position_out_of_bounds} =
               Validation.validate_position({999_999.0, 0.0, 0.0})

      assert {:error, :position_out_of_bounds} =
               Validation.validate_position({0.0, 999_999.0, 0.0})

      assert {:error, :position_out_of_bounds} =
               Validation.validate_position({0.0, 0.0, 999_999.0})

      assert {:error, :position_out_of_bounds} =
               Validation.validate_position({-999_999.0, 0.0, 0.0})
    end

    test "rejects non-tuple values" do
      assert {:error, :invalid_position_type} = Validation.validate_position([100.0, 50.0, 200.0])
      assert {:error, :invalid_position_type} = Validation.validate_position(nil)
      assert {:error, :invalid_position_type} = Validation.validate_position(%{x: 1, y: 2, z: 3})
    end

    test "rejects non-numeric components" do
      assert {:error, :invalid_position_type} = Validation.validate_position({"100", 50.0, 200.0})
      assert {:error, :invalid_position_type} = Validation.validate_position({nil, 50.0, 200.0})
      assert {:error, :invalid_position_type} = Validation.validate_position({:atom, 50.0, 200.0})
    end

    test "rejects wrong tuple size" do
      assert {:error, :invalid_position_type} = Validation.validate_position({100.0, 50.0})

      assert {:error, :invalid_position_type} =
               Validation.validate_position({100.0, 50.0, 200.0, 300.0})
    end
  end

  describe "is_nan_or_inf/1" do
    # NaN/Infinity cannot be created in OTP 28+, but we test the function
    # works correctly for regular values (backward compatibility)

    test "returns false for regular floats" do
      refute Validation.is_nan_or_inf(0.0)
      refute Validation.is_nan_or_inf(100.5)
      refute Validation.is_nan_or_inf(-100.5)
      # Max float
      refute Validation.is_nan_or_inf(1.7976931348623157e308)
    end

    test "returns false for integers" do
      refute Validation.is_nan_or_inf(0)
      refute Validation.is_nan_or_inf(100)
      refute Validation.is_nan_or_inf(-100)
    end
  end

  describe "validate_string/2" do
    test "accepts valid string" do
      assert :ok = Validation.validate_string("hello")
      assert :ok = Validation.validate_string("")
      assert :ok = Validation.validate_string("Unicode: 你好 🎮")
    end

    test "rejects non-string values" do
      assert {:error, :not_a_string} = Validation.validate_string(123)
      assert {:error, :not_a_string} = Validation.validate_string(nil)
      assert {:error, :not_a_string} = Validation.validate_string(['h', 'i'])
    end

    test "rejects empty string when allow_empty: false" do
      assert {:error, :empty_string} = Validation.validate_string("", allow_empty: false)
    end

    test "allows empty string by default" do
      assert :ok = Validation.validate_string("")
    end

    test "rejects string exceeding max_length" do
      long_string = String.duplicate("a", 5000)
      assert {:error, :string_too_long} = Validation.validate_string(long_string)

      # Custom max_length
      assert {:error, :string_too_long} = Validation.validate_string("hello", max_length: 3)
    end

    test "rejects invalid UTF-8" do
      invalid_utf8 = <<0xFF, 0xFE>>
      assert {:error, :invalid_utf8} = Validation.validate_string(invalid_utf8)
    end
  end

  describe "validate_name/1" do
    test "accepts valid names" do
      assert :ok = Validation.validate_name("PlayerOne")
      assert :ok = Validation.validate_name("Test123")
      assert :ok = Validation.validate_name("abc")
    end

    test "rejects names starting with number" do
      assert {:error, :invalid_name_format} = Validation.validate_name("123Player")
    end

    test "rejects names with special characters" do
      assert {:error, :invalid_name_format} = Validation.validate_name("Player_One")
      assert {:error, :invalid_name_format} = Validation.validate_name("Player-One")
      assert {:error, :invalid_name_format} = Validation.validate_name("Player One")
    end

    test "rejects names too short" do
      assert {:error, :name_too_short} = Validation.validate_name("AB")
      assert {:error, :name_too_short} = Validation.validate_name("A")
    end

    test "rejects empty name" do
      assert {:error, :empty_string} = Validation.validate_name("")
    end

    test "rejects names too long" do
      long_name = String.duplicate("a", 65)
      assert {:error, :string_too_long} = Validation.validate_name(long_name)
    end
  end

  describe "validate_chat_message/1" do
    test "accepts valid chat messages" do
      assert :ok = Validation.validate_chat_message("Hello, world!")
      assert :ok = Validation.validate_chat_message("Unicode: 你好 🎮")
    end

    test "rejects messages exceeding limit" do
      long_message = String.duplicate("a", 1025)
      assert {:error, :string_too_long} = Validation.validate_chat_message(long_message)
    end
  end

  describe "validate_enum/2" do
    test "accepts value in allowed set" do
      assert :ok = Validation.validate_enum(1, [1, 2, 3])
      assert :ok = Validation.validate_enum(:foo, [:foo, :bar, :baz])
    end

    test "rejects value not in allowed set" do
      assert {:error, {:invalid_enum, 5, [1, 2, 3]}} = Validation.validate_enum(5, [1, 2, 3])

      assert {:error, {:invalid_enum, :qux, [:foo, :bar]}} =
               Validation.validate_enum(:qux, [:foo, :bar])
    end
  end

  describe "validate_range/3" do
    test "accepts value in range" do
      assert :ok = Validation.validate_range(5, 1, 10)
      # Lower bound
      assert :ok = Validation.validate_range(1, 1, 10)
      # Upper bound
      assert :ok = Validation.validate_range(10, 1, 10)
    end

    test "rejects value below range" do
      assert {:error, {:out_of_range, 0, 1, 10}} = Validation.validate_range(0, 1, 10)
    end

    test "rejects value above range" do
      assert {:error, {:out_of_range, 15, 1, 10}} = Validation.validate_range(15, 1, 10)
    end

    test "rejects non-integer values" do
      assert {:error, {:out_of_range, 5.5, 1, 10}} = Validation.validate_range(5.5, 1, 10)
    end
  end

  describe "validate_all/1" do
    test "returns :ok when all validations pass" do
      result =
        Validation.validate_all([
          {&Validation.validate_position/1, [{100.0, 50.0, 200.0}]},
          {&Validation.validate_string/1, ["hello"]}
        ])

      assert :ok = result
    end

    test "returns first error when validation fails" do
      result =
        Validation.validate_all([
          {&Validation.validate_position/1, [{999_999.0, 0.0, 0.0}]},
          {&Validation.validate_string/1, ["hello"]}
        ])

      assert {:error, :position_out_of_bounds} = result
    end

    test "short-circuits on first error" do
      result =
        Validation.validate_all([
          # This fails first
          {&Validation.validate_string/1, [123]},
          {&Validation.validate_position/1, [{999_999.0, 0.0, 0.0}]}
        ])

      assert {:error, :not_a_string} = result
    end
  end

  describe "validate_race/1" do
    test "accepts valid races" do
      for race <- [1, 3, 4, 5, 12, 13, 16] do
        assert :ok = Validation.validate_race(race)
      end
    end

    test "rejects invalid races" do
      assert {:error, :invalid_race} = Validation.validate_race(0)
      assert {:error, :invalid_race} = Validation.validate_race(999)
    end
  end

  describe "validate_class/1" do
    test "accepts valid classes" do
      for class <- [1, 2, 3, 4, 5, 7] do
        assert :ok = Validation.validate_class(class)
      end
    end

    test "rejects invalid classes" do
      assert {:error, :invalid_class} = Validation.validate_class(0)
      assert {:error, :invalid_class} = Validation.validate_class(6)
      assert {:error, :invalid_class} = Validation.validate_class(999)
    end
  end

  describe "validate_faction/1" do
    test "accepts valid factions" do
      # Exile
      assert :ok = Validation.validate_faction(166)
      # Dominion
      assert :ok = Validation.validate_faction(167)
    end

    test "rejects invalid factions" do
      assert {:error, :invalid_faction} = Validation.validate_faction(0)
      assert {:error, :invalid_faction} = Validation.validate_faction(168)
    end
  end

  describe "validate_level/1" do
    test "accepts valid levels" do
      assert :ok = Validation.validate_level(1)
      assert :ok = Validation.validate_level(25)
      assert :ok = Validation.validate_level(50)
    end

    test "rejects invalid levels" do
      assert {:error, {:out_of_range, 0, 1, 50}} = Validation.validate_level(0)
      assert {:error, {:out_of_range, 51, 1, 50}} = Validation.validate_level(51)
    end
  end
end
