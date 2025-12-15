defmodule BezgelorWorld.Cinematic.Actor do
  @moduledoc """
  Represents an actor (entity) in a cinematic sequence.

  Actors are spawned entities that participate in the cinematic,
  such as NPCs, creatures, or the player themselves.
  """

  alias BezgelorProtocol.Packets.World.{
    ServerCinematicActor,
    ServerCinematicActorAngle,
    ServerCinematicVisualEffect,
    ServerCinematicActorVisibility
  }

  @type position :: %{
          x: float(),
          y: float(),
          z: float(),
          rx: float(),
          ry: float(),
          rz: float(),
          rw: float()
        }

  @type t :: %__MODULE__{
          id: non_neg_integer(),
          creature_type: non_neg_integer(),
          flags: non_neg_integer(),
          unknown0: non_neg_integer(),
          movement_mode: non_neg_integer(),
          angle: float() | nil,
          position: position(),
          initial_delay: non_neg_integer(),
          active_prop_id: non_neg_integer(),
          socket_id: non_neg_integer(),
          visual_effects: list(),
          visibility_keyframes: list()
        }

  defstruct id: 0,
            creature_type: 0,
            flags: 0,
            unknown0: 10,
            movement_mode: 3,
            angle: nil,
            position: %{x: 0.0, y: 0.0, z: 0.0, rx: 0.0, ry: 0.0, rz: 0.0, rw: 1.0},
            initial_delay: 0,
            active_prop_id: 0,
            socket_id: 0,
            visual_effects: [],
            visibility_keyframes: []

  @doc """
  Create a new actor with the given parameters.
  """
  @spec new(non_neg_integer(), Keyword.t()) :: t()
  def new(creature_type, opts \\ []) do
    id = Keyword.get(opts, :id, generate_id())

    %__MODULE__{
      id: id,
      creature_type: creature_type,
      flags: Keyword.get(opts, :flags, 7),
      unknown0: Keyword.get(opts, :unknown0, 10),
      movement_mode: Keyword.get(opts, :movement_mode, 3),
      angle: Keyword.get(opts, :angle),
      position: Keyword.get(opts, :position, default_position()),
      initial_delay: Keyword.get(opts, :delay, 0),
      active_prop_id: Keyword.get(opts, :active_prop_id, 0),
      socket_id: Keyword.get(opts, :socket_id, 0),
      visual_effects: [],
      visibility_keyframes: []
    }
  end

  @doc """
  Add a visual effect to the actor.
  """
  @spec add_visual_effect(t(), map()) :: t()
  def add_visual_effect(actor, effect) do
    effect_with_actor = Map.put(effect, :unit_id, actor.id)
    %{actor | visual_effects: actor.visual_effects ++ [effect_with_actor]}
  end

  @doc """
  Add a visibility keyframe (show/hide at specific delay).
  """
  @spec add_visibility(t(), non_neg_integer(), boolean()) :: t()
  def add_visibility(actor, delay, hide) do
    keyframe = %{delay: delay, unit_id: actor.id, hide: hide}
    %{actor | visibility_keyframes: actor.visibility_keyframes ++ [keyframe]}
  end

  @doc """
  Generate packets for this actor.
  """
  @spec to_packets(t()) :: list()
  def to_packets(actor) do
    packets = [
      %ServerCinematicActor{
        delay: actor.initial_delay,
        flags: actor.flags,
        unknown0: actor.unknown0,
        spawn_handle: actor.id,
        creature_type: actor.creature_type,
        movement_mode: actor.movement_mode,
        position: actor.position,
        active_prop_id: actor.active_prop_id,
        socket_id: actor.socket_id
      }
    ]

    # Add angle packet if specified
    packets =
      if actor.angle do
        packets ++
          [
            %ServerCinematicActorAngle{
              delay: 0,
              unit_id: actor.id,
              angle: actor.angle
            }
          ]
      else
        packets
      end

    # Add visual effects
    packets =
      packets ++
        Enum.map(actor.visual_effects, fn effect ->
          %ServerCinematicVisualEffect{
            delay: Map.get(effect, :delay, 0),
            visual_handle: Map.get(effect, :visual_handle, 0),
            visual_effect_id: Map.get(effect, :visual_effect_id, 0),
            unit_id: effect.unit_id,
            position: Map.get(effect, :position, actor.position),
            remove_on_camera_end: Map.get(effect, :remove_on_camera_end, false)
          }
        end)

    # Add visibility keyframes
    packets ++
      Enum.map(actor.visibility_keyframes, fn keyframe ->
        %ServerCinematicActorVisibility{
          delay: keyframe.delay,
          unit_id: keyframe.unit_id,
          hide: keyframe.hide,
          unknown0: false
        }
      end)
  end

  # Private functions

  defp generate_id do
    :erlang.unique_integer([:positive, :monotonic])
  end

  defp default_position do
    %{x: 0.0, y: 0.0, z: 0.0, rx: 0.0, ry: 0.0, rz: 0.0, rw: 1.0}
  end
end
