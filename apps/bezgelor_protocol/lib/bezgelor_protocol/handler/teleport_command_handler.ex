defmodule BezgelorProtocol.Handler.TeleportCommandHandler do
  @moduledoc """
  Handler for /teleport chat command (GM command).

  ## Usage

  In chat:
  - `/teleport <world_location_id>` - Teleport to world location
  - `/teleport <x> <y> <z>` - Teleport to coordinates in current zone
  - `/teleport <world_id> <x> <y> <z>` - Teleport to coordinates in specified world

  ## Examples

      /teleport 50231       # Teleport to Exile tutorial start
      /teleport 100 50 200  # Teleport to x=100, y=50, z=200 in current zone
  """

  # Suppress compile-order warning - module is in bezgelor_world which compiles after protocol
  @compile {:no_warn_undefined, BezgelorWorld.Teleport}

  alias BezgelorWorld.Teleport

  require Logger

  @doc """
  Parse and execute teleport command.

  Returns {:ok, updated_session} on success, or {:error, reason} on failure.
  """
  @spec handle(String.t(), map()) :: {:ok, map()} | {:error, atom()}
  def handle(args, session) do
    args
    |> String.trim()
    |> String.split(~r/\s+/)
    |> parse_and_execute(session)
  end

  # Single argument: world location ID
  defp parse_and_execute([world_location_id_str], session) do
    case Integer.parse(world_location_id_str) do
      {world_location_id, ""} ->
        Teleport.to_world_location(session, world_location_id)

      _ ->
        {:error, :invalid_arguments}
    end
  end

  # Three arguments: x y z (current zone)
  defp parse_and_execute([x_str, y_str, z_str], session) do
    with {x, ""} <- Float.parse(x_str),
         {y, ""} <- Float.parse(y_str),
         {z, ""} <- Float.parse(z_str) do
      world_id = get_in(session, [:session_data, :world_id]) || 426
      Teleport.to_position(session, world_id, {x, y, z})
    else
      _ -> {:error, :invalid_arguments}
    end
  end

  # Four arguments: world_id x y z
  defp parse_and_execute([world_id_str, x_str, y_str, z_str], session) do
    with {world_id, ""} <- Integer.parse(world_id_str),
         {x, ""} <- Float.parse(x_str),
         {y, ""} <- Float.parse(y_str),
         {z, ""} <- Float.parse(z_str) do
      Teleport.to_position(session, world_id, {x, y, z})
    else
      _ -> {:error, :invalid_arguments}
    end
  end

  defp parse_and_execute(_, _session) do
    {:error, :invalid_arguments}
  end
end
