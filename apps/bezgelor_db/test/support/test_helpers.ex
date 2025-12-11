defmodule BezgelorDb.TestHelpers do
  @moduledoc """
  Test helper functions for BezgelorDb tests.
  """

  @doc """
  Extracts errors from a changeset as a map of field => [error messages].
  """
  def errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
