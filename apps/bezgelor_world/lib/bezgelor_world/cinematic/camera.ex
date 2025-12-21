defmodule BezgelorWorld.Cinematic.Camera do
  @moduledoc """
  Represents camera movements and actions in a cinematic sequence.

  Cameras can be attached to actors, follow splines, or have transitions.
  """

  alias BezgelorWorld.Cinematic.Actor

  alias BezgelorProtocol.Packets.World.{
    ServerCinematicActorAttach,
    ServerCinematicCameraSpline,
    ServerCinematicTransitionDurationSet
  }

  @type action ::
          {:attach, map()}
          | {:spline, map()}
          | {:transition, map()}

  @type t :: %__MODULE__{
          actor: Actor.t() | nil,
          actions: [action()]
        }

  defstruct actor: nil,
            actions: []

  @doc """
  Create a camera attached to an actor.
  """
  @spec attached_to_actor(Actor.t(), Keyword.t()) :: t()
  def attached_to_actor(actor, opts \\ []) do
    attach_id = Keyword.get(opts, :attach_id, actor.id)
    attach_type = Keyword.get(opts, :attach_type, 0)
    use_rotation = Keyword.get(opts, :use_rotation, true)
    transition_type = Keyword.get(opts, :transition_type, 0)
    transition_start = Keyword.get(opts, :transition_start, 1500)
    transition_mid = Keyword.get(opts, :transition_mid, 0)
    transition_end = Keyword.get(opts, :transition_end, 1500)

    %__MODULE__{
      actor: actor,
      actions: [
        {:attach,
         %{delay: 0, attach_id: attach_id, attach_type: attach_type, use_rotation: use_rotation}},
        {:transition,
         %{
           delay: 0,
           type: transition_type,
           start: transition_start,
           mid: transition_mid,
           end: transition_end
         }}
      ]
    }
  end

  @doc """
  Create a camera following a spline path.
  """
  @spec from_spline(non_neg_integer(), Keyword.t()) :: t()
  def from_spline(spline_id, opts \\ []) do
    %__MODULE__{
      actor: nil,
      actions: [
        {:spline,
         %{
           delay: Keyword.get(opts, :delay, 0),
           spline: spline_id,
           spline_mode: Keyword.get(opts, :spline_mode, 0),
           speed: Keyword.get(opts, :speed, 1.0),
           target: Keyword.get(opts, :target, false),
           use_rotation: Keyword.get(opts, :use_rotation, true)
         }}
      ]
    }
  end

  @doc """
  Add an attach action to the camera.
  """
  @spec add_attach(t(), non_neg_integer(), non_neg_integer(), Keyword.t()) :: t()
  def add_attach(camera, delay, attach_id, opts \\ []) do
    action =
      {:attach,
       %{
         delay: delay,
         attach_id: attach_id,
         attach_type: Keyword.get(opts, :attach_type, 0),
         use_rotation: Keyword.get(opts, :use_rotation, true)
       }}

    %{camera | actions: camera.actions ++ [action]}
  end

  @doc """
  Add a transition action to the camera.
  """
  @spec add_transition(t(), non_neg_integer(), non_neg_integer(), Keyword.t()) :: t()
  def add_transition(camera, delay, type, opts \\ []) do
    action =
      {:transition,
       %{
         delay: delay,
         type: type,
         start: Keyword.get(opts, :start, 1500),
         mid: Keyword.get(opts, :mid, 0),
         end: Keyword.get(opts, :end_duration, 1500)
       }}

    %{camera | actions: camera.actions ++ [action]}
  end

  @doc """
  Generate packets for this camera.
  """
  @spec to_packets(t()) :: list()
  def to_packets(camera) do
    Enum.map(camera.actions, &action_to_packet(&1, camera))
  end

  # Private functions

  defp action_to_packet({:attach, params}, camera) do
    parent_unit = if camera.actor, do: camera.actor.id, else: 0

    %ServerCinematicActorAttach{
      attach_type: params.attach_type,
      attach_id: params.attach_id,
      delay: params.delay,
      parent_unit: parent_unit,
      use_rotation: params.use_rotation
    }
  end

  defp action_to_packet({:spline, params}, _camera) do
    %ServerCinematicCameraSpline{
      delay: params.delay,
      spline: params.spline,
      spline_mode: params.spline_mode,
      speed: params.speed,
      target: params.target,
      use_rotation: params.use_rotation
    }
  end

  defp action_to_packet({:transition, params}, _camera) do
    %ServerCinematicTransitionDurationSet{
      type: params.type,
      duration_start: params.start,
      duration_mid: params.mid,
      duration_end: params[:end] || 1500
    }
  end
end
