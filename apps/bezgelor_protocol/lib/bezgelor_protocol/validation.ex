defmodule BezgelorProtocol.Validation do
  @moduledoc """
  Packet field validation utilities.

  Provides validation functions for common packet fields to prevent exploits
  and ensure data integrity:
  - Position validation (NaN/Inf detection, bounds checking)
  - String validation (length limits, UTF-8 validation)
  - Name validation (format rules)
  - Enum validation (allowed values)
  - Range validation (integer bounds)

  ## Usage

      alias BezgelorProtocol.Validation

      # Position validation
      :ok = Validation.validate_position({100.0, 50.0, 200.0})
      {:error, :position_out_of_bounds} = Validation.validate_position({999_999.0, 0.0, 0.0})

      # String validation
      :ok = Validation.validate_string("hello")
      {:error, :string_too_long} = Validation.validate_string(large_string, max_length: 100)

      # Name validation
      :ok = Validation.validate_name("PlayerOne")
      {:error, :invalid_name_format} = Validation.validate_name("123abc")

      # Enum validation
      :ok = Validation.validate_enum(1, [1, 2, 3])
      {:error, {:invalid_enum, 5, [1, 2, 3]}} = Validation.validate_enum(5, [1, 2, 3])
  """

  @max_string_length 4096
  @max_name_length 64
  @max_chat_length 1024
  @position_bounds 100_000.0

  # Position validation

  @doc """
  Validate a position tuple contains valid floats.

  Returns `:ok` for valid positions or `{:error, reason}` for invalid ones.

  ## Validations
  - All components must be numbers (integer or float)
  - No NaN or Infinity values
  - Position must be within bounds (±100,000 units)

  ## Examples

      iex> Validation.validate_position({100.0, 50.0, 200.0})
      :ok

      iex> Validation.validate_position({999_999.0, 0.0, 0.0})
      {:error, :position_out_of_bounds}
  """
  @spec validate_position({number(), number(), number()}) ::
          :ok
          | {:error, :invalid_position_type | :invalid_position_value | :position_out_of_bounds}
  def validate_position({x, y, z}) do
    cond do
      not is_number(x) or not is_number(y) or not is_number(z) ->
        {:error, :invalid_position_type}

      is_nan_or_inf(x) or is_nan_or_inf(y) or is_nan_or_inf(z) ->
        {:error, :invalid_position_value}

      abs(x) > @position_bounds or abs(y) > @position_bounds or abs(z) > @position_bounds ->
        {:error, :position_out_of_bounds}

      true ->
        :ok
    end
  end

  def validate_position(_), do: {:error, :invalid_position_type}

  # Maximum finite float value (approximately 1.7976931348623157e308)
  @max_float 1.7976931348623157e308

  @doc """
  Check if a float value is NaN or Infinity.

  Uses IEEE 754 properties:
  - NaN is the only value that doesn't equal itself
  - Infinity values exceed the max representable float

  Note: OTP 28+ provides built-in protection against NaN/Infinity.
  Binary pattern matches fail when attempting to decode these values.
  This function remains for backward compatibility with older OTP versions.
  """
  @spec is_nan_or_inf(number()) :: boolean()
  def is_nan_or_inf(val) when is_float(val) do
    # NaN is the only value that doesn't equal itself
    # Infinity exceeds the max float bounds
    val != val or abs(val) > @max_float
  end

  def is_nan_or_inf(_), do: false

  # String validation

  @doc """
  Validate a string field.

  ## Options
  - `:max_length` - Maximum byte size (default: 4096)
  - `:allow_empty` - Whether empty strings are allowed (default: true)

  ## Examples

      iex> Validation.validate_string("hello")
      :ok

      iex> Validation.validate_string("", allow_empty: false)
      {:error, :empty_string}
  """
  @spec validate_string(term(), keyword()) ::
          :ok | {:error, :not_a_string | :empty_string | :string_too_long | :invalid_utf8}
  def validate_string(str, opts \\ []) do
    max_length = Keyword.get(opts, :max_length, @max_string_length)
    allow_empty = Keyword.get(opts, :allow_empty, true)

    cond do
      not is_binary(str) ->
        {:error, :not_a_string}

      not allow_empty and byte_size(str) == 0 ->
        {:error, :empty_string}

      byte_size(str) > max_length ->
        {:error, :string_too_long}

      not String.valid?(str) ->
        {:error, :invalid_utf8}

      true ->
        :ok
    end
  end

  @doc """
  Validate a character name.

  Names must:
  - Be 3-64 characters
  - Start with a letter
  - Contain only letters and numbers
  - Be valid UTF-8

  ## Examples

      iex> Validation.validate_name("PlayerOne")
      :ok

      iex> Validation.validate_name("123abc")
      {:error, :invalid_name_format}

      iex> Validation.validate_name("AB")
      {:error, :name_too_short}
  """
  @spec validate_name(term()) ::
          :ok
          | {:error,
             :not_a_string
             | :empty_string
             | :string_too_long
             | :invalid_utf8
             | :invalid_name_format
             | :name_too_short}
  def validate_name(name) do
    with :ok <- validate_string(name, max_length: @max_name_length, allow_empty: false) do
      cond do
        not Regex.match?(~r/^[a-zA-Z][a-zA-Z0-9]*$/, name) ->
          {:error, :invalid_name_format}

        String.length(name) < 3 ->
          {:error, :name_too_short}

        true ->
          :ok
      end
    end
  end

  @doc """
  Validate a chat message.

  Chat messages have a 1024 character limit and must be valid UTF-8.

  ## Examples

      iex> Validation.validate_chat_message("Hello, world!")
      :ok
  """
  @spec validate_chat_message(term()) ::
          :ok | {:error, :not_a_string | :empty_string | :string_too_long | :invalid_utf8}
  def validate_chat_message(message) do
    validate_string(message, max_length: @max_chat_length)
  end

  # Enum validation

  @doc """
  Validate value is in allowed set.

  ## Examples

      iex> Validation.validate_enum(1, [1, 2, 3])
      :ok

      iex> Validation.validate_enum(5, [1, 2, 3])
      {:error, {:invalid_enum, 5, [1, 2, 3]}}
  """
  @spec validate_enum(term(), [term()]) :: :ok | {:error, {:invalid_enum, term(), [term()]}}
  def validate_enum(value, allowed) when is_list(allowed) do
    if value in allowed do
      :ok
    else
      {:error, {:invalid_enum, value, allowed}}
    end
  end

  # Range validation

  @doc """
  Validate integer is in range (inclusive).

  ## Examples

      iex> Validation.validate_range(5, 1, 10)
      :ok

      iex> Validation.validate_range(15, 1, 10)
      {:error, {:out_of_range, 15, 1, 10}}
  """
  @spec validate_range(integer(), integer(), integer()) ::
          :ok | {:error, {:out_of_range, integer(), integer(), integer()}}
  def validate_range(value, min, max) when is_integer(value) do
    if value >= min and value <= max do
      :ok
    else
      {:error, {:out_of_range, value, min, max}}
    end
  end

  def validate_range(value, min, max), do: {:error, {:out_of_range, value, min, max}}

  # Convenience macros for validation pipelines

  @doc """
  Run multiple validations, returning first error or :ok.

  ## Examples

      Validation.validate_all([
        {&Validation.validate_position/1, [position]},
        {&Validation.validate_string/1, [name]}
      ])
  """
  @spec validate_all([{function(), [term()]}]) :: :ok | {:error, term()}
  def validate_all(validations) when is_list(validations) do
    Enum.reduce_while(validations, :ok, fn {fun, args}, :ok ->
      case apply(fun, args) do
        :ok -> {:cont, :ok}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  # Game-specific validators

  @doc """
  Validate race ID is valid.

  Race IDs in WildStar:
  - 1: Human
  - 3: Granok
  - 4: Aurin
  - 5: Draken
  - 12: Mechari
  - 13: Mordesh
  - 16: Chua
  """
  @valid_races [1, 3, 4, 5, 12, 13, 16]
  @spec validate_race(integer()) :: :ok | {:error, :invalid_race}
  def validate_race(race_id) when race_id in @valid_races, do: :ok
  def validate_race(_), do: {:error, :invalid_race}

  @doc """
  Validate class ID is valid.

  Class IDs in WildStar:
  - 1: Warrior
  - 2: Engineer
  - 3: Esper
  - 4: Medic
  - 5: Stalker
  - 7: Spellslinger
  """
  @valid_classes [1, 2, 3, 4, 5, 7]
  @spec validate_class(integer()) :: :ok | {:error, :invalid_class}
  def validate_class(class_id) when class_id in @valid_classes, do: :ok
  def validate_class(_), do: {:error, :invalid_class}

  @doc """
  Validate faction ID is valid.

  Faction IDs:
  - 166: Exile
  - 167: Dominion
  """
  @valid_factions [166, 167]
  @spec validate_faction(integer()) :: :ok | {:error, :invalid_faction}
  def validate_faction(faction_id) when faction_id in @valid_factions, do: :ok
  def validate_faction(_), do: {:error, :invalid_faction}

  @doc """
  Validate character level is within bounds.
  """
  @spec validate_level(integer()) ::
          :ok | {:error, {:out_of_range, integer(), integer(), integer()}}
  def validate_level(level), do: validate_range(level, 1, 50)
end
