defmodule BezgelorWorld.Cinematic.Transition do
  @moduledoc """
  Represents a screen transition effect (fade in/out) in a cinematic.
  """

  alias BezgelorProtocol.Packets.World.ServerCinematicTransition

  @type t :: %__MODULE__{
          delay: non_neg_integer(),
          flags: non_neg_integer(),
          end_tran: non_neg_integer(),
          tran_duration_start: non_neg_integer(),
          tran_duration_mid: non_neg_integer(),
          tran_duration_end: non_neg_integer()
        }

  defstruct delay: 0,
            flags: 0,
            end_tran: 0,
            tran_duration_start: 0,
            tran_duration_mid: 0,
            tran_duration_end: 0

  @doc """
  Create a fade-out transition.
  """
  @spec fade_out(non_neg_integer(), Keyword.t()) :: t()
  def fade_out(delay \\ 0, opts \\ []) do
    %__MODULE__{
      delay: delay,
      flags: Keyword.get(opts, :flags, 0),
      end_tran: Keyword.get(opts, :end_tran, 0),
      tran_duration_start: Keyword.get(opts, :start, 0),
      tran_duration_mid: Keyword.get(opts, :mid, 0),
      tran_duration_end: Keyword.get(opts, :end_duration, 0)
    }
  end

  @doc """
  Create a fade-in transition.
  """
  @spec fade_in(non_neg_integer(), Keyword.t()) :: t()
  def fade_in(delay \\ 0, opts \\ []) do
    %__MODULE__{
      delay: delay,
      flags: Keyword.get(opts, :flags, 1),
      end_tran: Keyword.get(opts, :end_tran, 1),
      tran_duration_start: Keyword.get(opts, :start, 0),
      tran_duration_mid: Keyword.get(opts, :mid, 0),
      tran_duration_end: Keyword.get(opts, :end_duration, 0)
    }
  end

  @doc """
  Create a custom transition.
  """
  @spec new(Keyword.t()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      delay: Keyword.get(opts, :delay, 0),
      flags: Keyword.get(opts, :flags, 0),
      end_tran: Keyword.get(opts, :end_tran, 0),
      tran_duration_start: Keyword.get(opts, :start, 0),
      tran_duration_mid: Keyword.get(opts, :mid, 0),
      tran_duration_end: Keyword.get(opts, :end_duration, 0)
    }
  end

  @doc """
  Convert to packet.
  """
  @spec to_packet(t()) :: ServerCinematicTransition.t()
  def to_packet(transition) do
    %ServerCinematicTransition{
      delay: transition.delay,
      flags: transition.flags,
      end_tran: transition.end_tran,
      tran_duration_start: transition.tran_duration_start,
      tran_duration_mid: transition.tran_duration_mid,
      tran_duration_end: transition.tran_duration_end
    }
  end
end
