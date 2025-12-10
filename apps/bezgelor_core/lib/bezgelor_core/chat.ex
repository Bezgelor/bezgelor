defmodule BezgelorCore.Chat do
  @moduledoc """
  Chat channel definitions and utilities.

  ## Overview

  This module defines chat channel types, their integer representations
  for packet serialization, and channel-specific properties like range.

  ## Channels

  | Channel | Value | Description | Range |
  |---------|-------|-------------|-------|
  | Say | 0 | Local chat | 30m |
  | Yell | 1 | Loud local chat | 100m |
  | Whisper | 2 | Private message | Global |
  | System | 3 | System messages | N/A |
  | Emote | 4 | Character emotes | 30m |
  | Party | 5 | Party chat | Party |
  | Guild | 6 | Guild chat | Guild |
  | Zone | 7 | Zone-wide chat | Zone |

  ## Usage

      iex> Chat.channel_to_int(:say)
      0

      iex> Chat.int_to_channel(0)
      :say

      iex> Chat.range(:say)
      30.0
  """

  @type channel ::
          :say
          | :yell
          | :whisper
          | :system
          | :emote
          | :party
          | :guild
          | :zone

  # Channel integer values
  @channel_say 0
  @channel_yell 1
  @channel_whisper 2
  @channel_system 3
  @channel_emote 4
  @channel_party 5
  @channel_guild 6
  @channel_zone 7

  # Channel ranges (in game units, approximately meters)
  @say_range 30.0
  @yell_range 100.0
  @emote_range 30.0

  @doc """
  Convert channel atom to integer for packet serialization.

  ## Examples

      iex> BezgelorCore.Chat.channel_to_int(:say)
      0

      iex> BezgelorCore.Chat.channel_to_int(:whisper)
      2
  """
  @spec channel_to_int(channel()) :: non_neg_integer()
  def channel_to_int(:say), do: @channel_say
  def channel_to_int(:yell), do: @channel_yell
  def channel_to_int(:whisper), do: @channel_whisper
  def channel_to_int(:system), do: @channel_system
  def channel_to_int(:emote), do: @channel_emote
  def channel_to_int(:party), do: @channel_party
  def channel_to_int(:guild), do: @channel_guild
  def channel_to_int(:zone), do: @channel_zone
  def channel_to_int(_), do: @channel_say

  @doc """
  Convert integer to channel atom.

  ## Examples

      iex> BezgelorCore.Chat.int_to_channel(0)
      :say

      iex> BezgelorCore.Chat.int_to_channel(2)
      :whisper
  """
  @spec int_to_channel(non_neg_integer()) :: channel()
  def int_to_channel(@channel_say), do: :say
  def int_to_channel(@channel_yell), do: :yell
  def int_to_channel(@channel_whisper), do: :whisper
  def int_to_channel(@channel_system), do: :system
  def int_to_channel(@channel_emote), do: :emote
  def int_to_channel(@channel_party), do: :party
  def int_to_channel(@channel_guild), do: :guild
  def int_to_channel(@channel_zone), do: :zone
  def int_to_channel(_), do: :say

  @doc """
  Get the range for a channel (in game units).

  Returns nil for channels without range restrictions (whisper, system, party, guild).

  ## Examples

      iex> BezgelorCore.Chat.range(:say)
      30.0

      iex> BezgelorCore.Chat.range(:yell)
      100.0

      iex> BezgelorCore.Chat.range(:whisper)
      nil
  """
  @spec range(channel()) :: float() | nil
  def range(:say), do: @say_range
  def range(:yell), do: @yell_range
  def range(:emote), do: @emote_range
  def range(_), do: nil

  @doc """
  Check if a channel requires a target (like whisper).
  """
  @spec requires_target?(channel()) :: boolean()
  def requires_target?(:whisper), do: true
  def requires_target?(_), do: false

  @doc """
  Check if a channel is local (range-based).
  """
  @spec local?(channel()) :: boolean()
  def local?(:say), do: true
  def local?(:yell), do: true
  def local?(:emote), do: true
  def local?(_), do: false

  @doc """
  Check if a channel is available (implemented in current phase).

  Party and guild chat require those systems to be implemented.
  """
  @spec available?(channel()) :: boolean()
  def available?(:say), do: true
  def available?(:yell), do: true
  def available?(:whisper), do: true
  def available?(:system), do: true
  def available?(:emote), do: true
  def available?(:zone), do: true
  def available?(:party), do: false
  def available?(:guild), do: false
  def available?(_), do: false

  @doc """
  List all available channels.
  """
  @spec available_channels() :: [channel()]
  def available_channels do
    [:say, :yell, :whisper, :system, :emote, :zone]
  end

  @doc """
  Get the maximum message length for chat.
  """
  @spec max_message_length() :: non_neg_integer()
  def max_message_length, do: 500
end
