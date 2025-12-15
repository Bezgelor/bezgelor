defmodule BezgelorCore.LogFormatter do
  @moduledoc """
  Custom log formatter that only shows the metadata separator when metadata exists.

  Format: `$time [$level] $message` or `$time [$level] $message | metadata` when user context exists.
  """

  @doc """
  Format a log message with conditional metadata separator.
  """
  def format(level, message, timestamp, metadata) do
    time = format_time(timestamp)
    level_str = to_string(level)

    # Only include metadata we care about (user context)
    user_metadata = format_metadata(metadata)

    if user_metadata == "" do
      "#{time} [#{level_str}] #{message}\n"
    else
      "#{time} [#{level_str}] #{message} | #{user_metadata}\n"
    end
  rescue
    _ -> "#{inspect(timestamp)} [#{level}] #{message} #{inspect(metadata)}\n"
  end

  defp format_time({date, {hour, minute, second, micro}}) do
    {year, month, day} = date

    :io_lib.format("~4..0B-~2..0B-~2..0B ~2..0B:~2..0B:~2..0B.~3..0B", [
      year,
      month,
      day,
      hour,
      minute,
      second,
      div(micro, 1000)
    ])
    |> IO.iodata_to_binary()
  end

  defp format_metadata(metadata) do
    # Only format the user-context metadata keys, showing just values
    # Order: account, char, conn_id (most relevant first)
    parts =
      [:account, :char, :conn_id]
      |> Enum.map(fn key -> Keyword.get(metadata, key) end)
      |> Enum.reject(&is_nil/1)
      |> Enum.map(&to_string/1)

    Enum.join(parts, " ")
  end
end
