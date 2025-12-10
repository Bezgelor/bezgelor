defmodule BezgelorCore.ChatCommand do
  @moduledoc """
  Chat command parsing and execution.

  ## Overview

  Commands start with "/" and perform special actions or
  send messages to specific channels.

  ## Built-in Commands

  | Command | Aliases | Description |
  |---------|---------|-------------|
  | /say | /s | Send local message |
  | /yell | /y | Send yell message |
  | /whisper | /w, /tell | Send private message |
  | /emote | /e, /me | Perform emote |
  | /who | | List nearby players |
  | /loc | /location | Show current location |

  ## Usage

      iex> ChatCommand.parse("/say Hello world")
      {:chat, :say, "Hello world"}

      iex> ChatCommand.parse("/w PlayerName Hi there")
      {:whisper, "PlayerName", "Hi there"}

      iex> ChatCommand.parse("/loc")
      {:action, :location, []}

      iex> ChatCommand.parse("Hello world")
      {:chat, :say, "Hello world"}
  """

  @type command_result ::
          {:chat, atom(), String.t()}
          | {:whisper, String.t(), String.t()}
          | {:action, atom(), list()}
          | {:error, atom()}

  @doc """
  Parse a chat message for commands.

  Messages starting with "/" are parsed as commands.
  Other messages are treated as :say channel chat.

  ## Examples

      iex> BezgelorCore.ChatCommand.parse("/yell Look out!")
      {:chat, :yell, "Look out!"}

      iex> BezgelorCore.ChatCommand.parse("Hello")
      {:chat, :say, "Hello"}
  """
  @spec parse(String.t()) :: command_result()
  def parse("/" <> rest) do
    parse_command(String.trim(rest))
  end

  def parse(message) do
    {:chat, :say, message}
  end

  # Parse command and arguments
  defp parse_command(text) do
    case String.split(text, " ", parts: 2) do
      [command] -> execute_command(String.downcase(command), "")
      [command, args] -> execute_command(String.downcase(command), args)
    end
  end

  # Say commands
  defp execute_command("say", message), do: {:chat, :say, message}
  defp execute_command("s", message), do: {:chat, :say, message}

  # Yell commands
  defp execute_command("yell", message), do: {:chat, :yell, message}
  defp execute_command("y", message), do: {:chat, :yell, message}

  # Whisper commands
  defp execute_command("whisper", args), do: parse_whisper(args)
  defp execute_command("w", args), do: parse_whisper(args)
  defp execute_command("tell", args), do: parse_whisper(args)

  # Emote commands
  defp execute_command("emote", message), do: {:chat, :emote, message}
  defp execute_command("e", message), do: {:chat, :emote, message}
  defp execute_command("me", message), do: {:chat, :emote, message}

  # Zone chat
  defp execute_command("zone", message), do: {:chat, :zone, message}
  defp execute_command("z", message), do: {:chat, :zone, message}

  # Action commands (no message payload)
  defp execute_command("who", _), do: {:action, :who, []}
  defp execute_command("loc", _), do: {:action, :location, []}
  defp execute_command("location", _), do: {:action, :location, []}

  # Unknown command
  defp execute_command(cmd, _) do
    {:error, {:unknown_command, cmd}}
  end

  # Parse whisper target and message
  defp parse_whisper("") do
    {:error, :whisper_no_target}
  end

  defp parse_whisper(args) do
    case String.split(args, " ", parts: 2) do
      [_target] ->
        {:error, :whisper_no_message}

      [target, message] ->
        {:whisper, target, message}
    end
  end

  @doc """
  Check if a message is a command.

  ## Examples

      iex> BezgelorCore.ChatCommand.command?("/say Hello")
      true

      iex> BezgelorCore.ChatCommand.command?("Hello")
      false
  """
  @spec command?(String.t()) :: boolean()
  def command?("/" <> _), do: true
  def command?(_), do: false
end
