defmodule BezgelorPortalWeb.Helpers.FormHelpers do
  @moduledoc """
  Shared helper functions for form parameter parsing and validation.
  """

  @doc """
  Parse a value as an integer, returning an error tuple if nil or invalid.

  ## Examples

      iex> parse_int("123", "Account ID")
      {:ok, 123}

      iex> parse_int(nil, "Account ID")
      {:error, "Account ID is required"}

      iex> parse_int("abc", "Account ID")
      {:error, "Account ID is invalid"}
  """
  @spec parse_int(String.t() | nil, String.t()) :: {:ok, integer()} | {:error, String.t()}
  def parse_int(nil, label), do: {:error, "#{label} is required"}

  def parse_int(value, label) do
    case Integer.parse(to_string(value)) do
      {int, ""} -> {:ok, int}
      _ -> {:error, "#{label} is invalid"}
    end
  end

  @doc """
  Parse a value as an integer, returning a default if nil or invalid.

  ## Examples

      iex> parse_int_default("123", 0)
      123

      iex> parse_int_default(nil, 0)
      0

      iex> parse_int_default("abc", 42)
      42
  """
  @spec parse_int_default(String.t() | nil, integer()) :: integer()
  def parse_int_default(nil, default), do: default

  def parse_int_default(value, default) when is_integer(default) do
    case Integer.parse(to_string(value)) do
      {int, ""} -> int
      _ -> default
    end
  end

  @doc """
  Check if a value is truthy (true, "true", "on", "1").

  ## Examples

      iex> truthy?(true)
      true

      iex> truthy?("true")
      true

      iex> truthy?("on")
      true

      iex> truthy?("1")
      true

      iex> truthy?(false)
      false

      iex> truthy?(nil)
      false
  """
  @spec truthy?(any()) :: boolean()
  def truthy?(value) when value in [true, "true", "on", "1"], do: true
  def truthy?(_), do: false

  @doc """
  Return the trimmed string value, or default if empty/nil.

  ## Examples

      iex> string_or_default("  hello  ", "default")
      "hello"

      iex> string_or_default("", "default")
      "default"

      iex> string_or_default(nil, "default")
      "default"
  """
  @spec string_or_default(String.t() | nil, String.t()) :: String.t()
  def string_or_default(value, default) when is_binary(value) do
    trimmed = String.trim(value)
    if trimmed == "", do: default, else: trimmed
  end

  def string_or_default(_, default), do: default

  @doc """
  Return the trimmed string or nil if empty/nil.

  ## Examples

      iex> blank_to_nil("  hello  ")
      "hello"

      iex> blank_to_nil("")
      nil

      iex> blank_to_nil(nil)
      nil
  """
  @spec blank_to_nil(String.t() | nil) :: String.t() | nil
  def blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  def blank_to_nil(_), do: nil

  @doc """
  Add a key-value pair to a keyword list if value is not nil.

  ## Examples

      iex> put_opt([], :name, "test")
      [name: "test"]

      iex> put_opt([], :name, nil)
      []
  """
  @spec put_opt(keyword(), atom(), any()) :: keyword()
  def put_opt(opts, _key, nil), do: opts
  def put_opt(opts, key, value), do: Keyword.put(opts, key, value)
end
