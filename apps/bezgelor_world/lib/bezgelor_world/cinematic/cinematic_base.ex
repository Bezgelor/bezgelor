defmodule BezgelorWorld.Cinematic.CinematicBase do
  @moduledoc """
  Base behaviour for cinematics.

  Cinematics are scripted sequences that control camera, actors, transitions,
  and subtitles. They are typically triggered on zone entry or quest completion.

  ## Usage

  Define a cinematic module that uses this behaviour:

      defmodule BezgelorWorld.Cinematic.Cinematics.NoviceTutorialOnEnter do
        use BezgelorWorld.Cinematic.CinematicBase

        @impl true
        def cinematic_id, do: 123

        @impl true
        def duration, do: 10000

        @impl true
        def setup(state) do
          state
          |> add_actor(Actor.new(12345, position: %{x: 100.0, y: 100.0, z: 0.0}))
          |> set_start_transition(Transition.fade_out())
          |> set_end_transition(Transition.fade_in())
        end
      end

  Then play it:

      NoviceTutorialOnEnter.play(session_data)
  """

  alias BezgelorWorld.Cinematic.{Actor, Camera, Transition}

  alias BezgelorProtocol.Packets.World.{
    ServerCinematicNotify,
    ServerCinematicComplete,
    ServerCinematicText,
    ServerCinematicShowAnimate,
    ServerCinematicActorVisibility
  }

  @type state :: %{
          cinematic_id: non_neg_integer(),
          duration: non_neg_integer(),
          initial_flags: non_neg_integer(),
          initial_cancel_mode: non_neg_integer(),
          actors: %{non_neg_integer() => Actor.t()},
          texts: [{non_neg_integer(), non_neg_integer()}],
          cameras: [Camera.t()],
          start_transition: Transition.t() | nil,
          end_transition: Transition.t() | nil,
          player_actor: Actor.t() | nil,
          session: map()
        }

  @callback cinematic_id() :: non_neg_integer()
  @callback duration() :: non_neg_integer()
  @callback initial_flags() :: non_neg_integer()
  @callback initial_cancel_mode() :: non_neg_integer()
  @callback setup(state()) :: state()

  defmacro __using__(_opts) do
    quote do
      @behaviour BezgelorWorld.Cinematic.CinematicBase

      alias BezgelorWorld.Cinematic.{Actor, Camera, Transition}
      alias BezgelorWorld.Cinematic.CinematicBase

      @impl true
      def initial_flags, do: 0

      @impl true
      def initial_cancel_mode, do: 0

      defoverridable initial_flags: 0, initial_cancel_mode: 0

      @doc """
      Play this cinematic for the given session.
      """
      @spec play(map()) :: {:ok, map(), list()}
      def play(session_data) do
        CinematicBase.play(__MODULE__, session_data)
      end
    end
  end

  @doc """
  Play a cinematic for the given session.
  """
  @spec play(module(), map()) :: {:ok, map(), list()}
  def play(cinematic_module, session_data) do
    state = init_state(cinematic_module, session_data)
    state = cinematic_module.setup(state)

    packets = build_packets(state)
    {:ok, session_data, packets}
  end

  @doc """
  Initialize cinematic state.
  """
  @spec init_state(module(), map()) :: state()
  def init_state(cinematic_module, session_data) do
    %{
      cinematic_id: cinematic_module.cinematic_id(),
      duration: cinematic_module.duration(),
      initial_flags: cinematic_module.initial_flags(),
      initial_cancel_mode: cinematic_module.initial_cancel_mode(),
      actors: %{},
      texts: [],
      cameras: [],
      start_transition: nil,
      end_transition: nil,
      player_actor: nil,
      session: session_data
    }
  end

  # State modification functions

  @doc """
  Add an actor to the cinematic.
  """
  @spec add_actor(state(), Actor.t()) :: state()
  def add_actor(state, actor) do
    %{state | actors: Map.put(state.actors, actor.id, actor)}
  end

  @doc """
  Add an actor with initial visual effects.
  """
  @spec add_actor(state(), Actor.t(), list()) :: state()
  def add_actor(state, actor, visual_effects) do
    actor = Enum.reduce(visual_effects, actor, &Actor.add_visual_effect(&2, &1))
    add_actor(state, actor)
  end

  @doc """
  Set the player actor (the actor the player controls during the cinematic).
  """
  @spec set_player_actor(state(), Actor.t()) :: state()
  def set_player_actor(state, actor) do
    %{state | player_actor: actor}
  end

  @doc """
  Add text (subtitle) to the cinematic.
  """
  @spec add_text(state(), non_neg_integer(), non_neg_integer(), non_neg_integer()) :: state()
  def add_text(state, text_id, start_time, end_time) do
    texts = state.texts ++ [{start_time, text_id}, {end_time, 0}]
    %{state | texts: texts}
  end

  @doc """
  Add a camera to the cinematic.
  """
  @spec add_camera(state(), Camera.t()) :: state()
  def add_camera(state, camera) do
    %{state | cameras: state.cameras ++ [camera]}
  end

  @doc """
  Set the start transition.
  """
  @spec set_start_transition(state(), Transition.t()) :: state()
  def set_start_transition(state, transition) do
    %{state | start_transition: transition}
  end

  @doc """
  Set the end transition.
  """
  @spec set_end_transition(state(), Transition.t()) :: state()
  def set_end_transition(state, transition) do
    %{state | end_transition: transition}
  end

  @doc """
  Get an actor by creature type.
  """
  @spec get_actor_by_type(state(), non_neg_integer()) :: Actor.t() | nil
  def get_actor_by_type(state, creature_type) do
    state.actors
    |> Map.values()
    |> Enum.find(&(&1.creature_type == creature_type))
  end

  # Packet building

  defp build_packets(state) do
    # Start notification
    start_notify = [
      %ServerCinematicNotify{
        flags: state.initial_flags,
        cancel: state.initial_cancel_mode,
        duration: state.duration,
        cinematic_id: state.cinematic_id
      }
    ]

    # Start transition
    start_trans =
      if state.start_transition do
        [Transition.to_packet(state.start_transition)]
      else
        []
      end

    # Actors
    actor_packets =
      state.actors
      |> Map.values()
      |> Enum.flat_map(&Actor.to_packets/1)

    # Player actor setup
    player_packets = build_player_packets(state)

    # Texts
    text_packets =
      Enum.map(state.texts, fn {delay, text_id} ->
        %ServerCinematicText{delay: delay, text_id: text_id}
      end)

    # Cameras
    camera_packets = Enum.flat_map(state.cameras, &Camera.to_packets/1)

    # End transition
    end_trans =
      if state.end_transition do
        [Transition.to_packet(state.end_transition)]
      else
        []
      end

    # End notification
    end_notify = [
      %ServerCinematicNotify{
        flags: 0,
        cancel: 0,
        duration: state.duration,
        cinematic_id: 0
      },
      %ServerCinematicComplete{}
    ]

    # Combine all packets in order
    start_notify ++
      start_trans ++
      actor_packets ++
      player_packets ++
      text_packets ++
      camera_packets ++
      end_trans ++
      end_notify
  end

  defp build_player_packets(state) do
    player_packets =
      if state.player_actor do
        Actor.to_packets(state.player_actor)
      else
        []
      end

    # Always show animate and hide player during cinematic
    player_packets ++
      [
        %ServerCinematicShowAnimate{delay: 0, show: true, animate: false},
        %ServerCinematicActorVisibility{delay: 0, unit_id: 0, hide: true, unknown0: false}
      ]
  end
end
