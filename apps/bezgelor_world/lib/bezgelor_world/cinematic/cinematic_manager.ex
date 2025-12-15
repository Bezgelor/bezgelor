defmodule BezgelorWorld.Cinematic.CinematicManager do
  @moduledoc """
  Manages cinematic playback for players.

  Triggers cinematics based on zone entry, quest completion, or other events.
  """

  # Suppress false positive warning - nil case is handled by pattern match
  @compile {:no_warn_undefined, {nil, :play, 1}}

  alias BezgelorWorld.Cinematic.Cinematics.NoviceTutorialOnEnter

  require Logger

  # Tutorial arkship zone IDs (Cryo Awakening Protocol zones)
  # From BezgelorCore.Zone - where new characters spawn
  @exile_arkship_zone 4844
  @dominion_arkship_zone 4813

  @doc """
  Check if a cinematic should play when entering a zone.
  Returns {:play, packets} if a cinematic should play, :none otherwise.

  NOTE: Tutorial cinematics are temporarily disabled because the NoviceTutorialOnEnter
  cinematic was designed for world 3460 (NPE) and its creature types/models don't
  exist in the actual tutorial arkship worlds (1634/1537). Playing the cinematic
  causes the client to lose zone tracking and get stuck on the loading screen.
  """
  @spec on_zone_enter(map(), non_neg_integer()) :: {:play, list()} | :none
  def on_zone_enter(_session_data, zone_id) do
    # Cinematics temporarily disabled - see moduledoc above
    Logger.debug("Cinematic check: zone_id=#{zone_id} - cinematics disabled")
    :none
  end

  @doc """
  Play a specific cinematic by ID for a player.
  """
  @spec play_cinematic(map(), non_neg_integer()) :: {:ok, map(), list()} | {:error, :unknown_cinematic}
  def play_cinematic(session_data, cinematic_id) do
    case get_cinematic_module(cinematic_id) do
      nil ->
        Logger.warning("Unknown cinematic ID: #{cinematic_id}")
        {:error, :unknown_cinematic}

      module ->
        module.play(session_data)
    end
  end

  # Private helpers
  # NOTE: These functions are currently unused because cinematics are disabled.
  # They will be needed when cinematics are re-enabled with proper world data.

  @doc false
  def tutorial_arkship?(zone_id) do
    zone_id in [@exile_arkship_zone, @dominion_arkship_zone]
  end

  @doc false
  def first_time_in_zone?(session_data, _zone_id) do
    # Check if this is a new character (level 1, no cinematics seen)
    character = Map.get(session_data, :character, %{})
    level = Map.get(character, :level, 1)

    # Only play tutorial cinematic for new characters
    level == 1
  end

  defp get_cinematic_module(cinematic_id) do
    # Map cinematic IDs to their implementation modules
    case cinematic_id do
      1 -> NoviceTutorialOnEnter
      _ -> nil
    end
  end
end
