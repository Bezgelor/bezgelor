defmodule BezgelorWorld.Cinematic.Cinematics.NoviceTutorialOnEnter do
  @moduledoc """
  Tutorial intro cinematic played when a new character enters the Arkship.

  This cinematic introduces the player to the game world, showing:
  - The cryopod bay where the player wakes up
  - The Nexus planet through a virtual display
  - Either Artemis Zin (Dominion) or Dorian Walker (Exile) as the guide

  Duration: 50 seconds
  """

  use BezgelorWorld.Cinematic.CinematicBase

  # Actor creature type IDs
  @actor_camera 73_425
  @actor_cryopods 73_426
  @actor_nexus 73_428
  @actor_props 73_430
  @actor_virtual_display 73_431
  @actor_player 73_429
  @actor_dorian 73_427
  @actor_dorian_holo 73_446
  @actor_artemis 73_484
  @actor_artemis_holo 73_584

  # Visual effect IDs
  @vfx_ambient 45_237
  @vfx_hologram 24_490

  # Race IDs for slot calculation
  @race_human 1
  @race_granok 4
  @race_draken 16
  @race_mechari 12
  @race_mordesh 5

  # Faction IDs
  @faction_exile 166
  @faction_dominion 167

  @impl true
  def cinematic_id, do: 1

  @impl true
  def duration, do: 50_000

  @impl true
  def initial_flags, do: 7

  @impl true
  def initial_cancel_mode, do: 2

  @impl true
  def setup(state) do
    session = state.session
    faction = get_faction(session)
    race = get_race(session)

    state
    |> CinematicBase.set_start_transition(Transition.new(delay: 0, flags: 1, end_tran: 2, start: 1500, mid: 0, end_duration: 1500))
    |> CinematicBase.set_end_transition(Transition.new(delay: 48_500, flags: 0, end_tran: 0))
    |> add_universal_actors(faction)
    |> add_faction_actor(faction)
    |> setup_camera()
    |> add_faction_texts(faction)
    |> setup_player_actor(race, faction)
  end

  # Private helpers

  defp get_faction(session) do
    character = Map.get(session, :character, %{})
    Map.get(character, :faction_id, @faction_exile)
  end

  defp get_race(session) do
    character = Map.get(session, :character, %{})
    Map.get(character, :race_id, @race_human)
  end

  # Faction-specific cinematic positions
  # These match the tutorial arkship spawn locations
  defp initial_position(@faction_exile) do
    # Exile: Gambler's Ruin (World 1634, Zone 4844)
    %{
      x: 4088.164551,
      y: -7.53978,
      z: -3.654721,
      rx: 0.0,
      ry: 0.0,
      rz: 0.0,
      rw: 1.0
    }
  end

  defp initial_position(@faction_dominion) do
    # Dominion: Destiny (World 1537, Zone 4813)
    %{
      x: 4605.650391,
      y: -7.57124,
      z: 494.995911,
      rx: 0.0,
      ry: 0.0,
      rz: 0.0,
      rw: 1.0
    }
  end

  defp initial_position(_), do: initial_position(@faction_exile)

  defp initial_angle, do: 3.1415929794311523

  defp add_universal_actors(state, faction) do
    pos = initial_position(faction)
    angle = initial_angle()

    # Add universal actors: camera, cryopods, nexus, props, virtual display, player placeholder
    universal_actors = [
      @actor_camera,
      @actor_cryopods,
      @actor_nexus,
      @actor_props,
      @actor_virtual_display,
      @actor_player
    ]

    Enum.reduce(universal_actors, state, fn creature_type, acc ->
      actor =
        Actor.new(creature_type,
          flags: 6,
          angle: angle,
          position: pos
        )

      visual_effect = %{visual_effect_id: @vfx_ambient, delay: 0}
      CinematicBase.add_actor(acc, actor, [visual_effect])
    end)
  end

  defp add_faction_actor(state, faction) do
    pos = initial_position(faction)
    angle = initial_angle()

    {faction_head, faction_holo} =
      if faction == @faction_dominion do
        {@actor_artemis, @actor_artemis_holo}
      else
        {@actor_dorian, @actor_dorian_holo}
      end

    # Add faction head actor
    head_actor =
      Actor.new(faction_head,
        flags: 6,
        angle: angle,
        position: pos
      )

    state = CinematicBase.add_actor(state, head_actor, [%{visual_effect_id: @vfx_ambient, delay: 0}])

    # Add faction holo actor with visibility flickering
    holo_actor =
      Actor.new(faction_holo,
        flags: 6,
        angle: angle,
        position: pos
      )
      |> Actor.add_visibility(9600, true)
      |> Actor.add_visibility(9700, false)
      |> Actor.add_visibility(9800, true)
      |> Actor.add_visibility(9933, false)
      |> Actor.add_visibility(10_500, true)

    CinematicBase.add_actor(state, holo_actor, [
      %{visual_effect_id: @vfx_ambient, delay: 0},
      %{visual_effect_id: @vfx_hologram, delay: 0}
    ])
  end

  defp setup_camera(state) do
    camera_actor = CinematicBase.get_actor_by_type(state, @actor_camera)

    if camera_actor do
      camera =
        Camera.attached_to_actor(camera_actor,
          attach_id: 7,
          attach_type: 0,
          use_rotation: true,
          transition_type: 0,
          transition_start: 1500,
          transition_mid: 0,
          transition_end: 1500
        )
        |> Camera.add_attach(31_000, 8, use_rotation: true)
        |> Camera.add_transition(31_000, 3, start: 1500, mid: 0, end_duration: 1500)

      CinematicBase.add_camera(state, camera)
    else
      state
    end
  end

  defp add_faction_texts(state, faction) do
    if faction == @faction_dominion do
      add_dominion_texts(state)
    else
      add_exile_texts(state)
    end
  end

  defp add_dominion_texts(state) do
    state
    |> CinematicBase.add_text(750_178, 1700, 5100)
    |> CinematicBase.add_text(750_179, 5133, 12_033)
    |> CinematicBase.add_text(750_180, 12_067, 16_400)
    |> CinematicBase.add_text(750_181, 16_433, 20_433)
    |> CinematicBase.add_text(750_182, 20_467, 23_733)
    |> CinematicBase.add_text(750_183, 23_767, 27_867)
    |> CinematicBase.add_text(750_184, 27_900, 34_400)
    |> CinematicBase.add_text(750_185, 34_433, 41_067)
    |> CinematicBase.add_text(750_186, 41_100, 43_800)
    |> CinematicBase.add_text(750_187, 43_833, 49_500)
  end

  defp add_exile_texts(state) do
    state
    |> CinematicBase.add_text(750_164, 1300, 5767)
    |> CinematicBase.add_text(750_165, 5800, 11_567)
    |> CinematicBase.add_text(750_166, 11_600, 16_467)
    |> CinematicBase.add_text(750_167, 16_500, 20_733)
    |> CinematicBase.add_text(750_168, 20_767, 23_633)
    |> CinematicBase.add_text(750_169, 23_667, 28_333)
    |> CinematicBase.add_text(750_170, 28_367, 34_333)
    |> CinematicBase.add_text(750_171, 34_367, 40_833)
    |> CinematicBase.add_text(750_173, 40_867, 44_567)
    |> CinematicBase.add_text(750_174, 44_600, 49_500)
  end

  defp setup_player_actor(state, race, faction) do
    pos = initial_position(faction)
    player_actor = CinematicBase.get_actor_by_type(state, @actor_player)

    # Slot depends on race for proper animation binding
    slot = get_race_slot(race)

    if player_actor do
      # The player actor is created with specific slot binding
      player_bind =
        Actor.new(0,
          id: 0,
          flags: 7,
          position: pos,
          unknown0: slot
        )

      CinematicBase.set_player_actor(state, player_bind)
    else
      state
    end
  end

  defp get_race_slot(race) do
    # Different races use different animation slot offsets
    case race do
      r when r in [@race_mechari, @race_mordesh, @race_granok, @race_human, @race_draken] -> 69
      _ -> 24
    end
  end
end
