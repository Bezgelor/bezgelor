defmodule BezgelorWorld.Handler.HousingHandler do
  @moduledoc """
  Handler for housing packets.

  ## Packets Handled
  - ClientHousingEnter - Request to enter a housing plot
  - ClientHousingExit - Request to leave current plot
  - ClientHousingDecorPlace/Move/Remove - Decor operations
  - ClientHousingFabkitInstall/Remove - FABkit operations
  - ClientHousingNeighborAdd/Remove - Neighbor management
  - ClientHousingRoommatePromote/Demote - Roommate management
  """

  @behaviour BezgelorProtocol.Handler

  require Logger

  alias BezgelorDb.Housing
  alias BezgelorWorld.HousingManager
  alias BezgelorProtocol.PacketReader

  alias BezgelorProtocol.Packets.World.{
    ServerHousingEnter,
    ServerHousingDecorUpdate,
    ServerHousingFabkitUpdate,
    ServerHousingNeighborList
  }

  @impl true
  def handle(payload, state) do
    reader = PacketReader.new(payload)

    # Read operation type byte
    case PacketReader.read_byte(reader) do
      {:ok, op_type, reader} ->
        handle_operation(op_type, reader, state)

      {:error, reason} ->
        Logger.warning("Failed to read housing operation type: #{inspect(reason)}")
        {:error, :invalid_packet}
    end
  end

  # Operation types
  @op_enter_own 0
  @op_enter_plot 1
  @op_exit 2
  @op_decor_place 3
  @op_decor_move 4
  @op_decor_remove 5
  @op_fabkit_install 6
  @op_fabkit_remove 7
  @op_neighbor_add 8
  @op_neighbor_remove 9
  @op_roommate_promote 10
  @op_roommate_demote 11

  defp handle_operation(@op_enter_own, _reader, state) do
    character_id = state.session_data[:character_id]

    case HousingManager.enter_own_plot(character_id) do
      {:ok, packets} ->
        {:ok, packets, state}

      {:error, :not_found} ->
        {:ok, [ServerHousingEnter.not_found()], state}

      {:error, :denied} ->
        {:ok, [ServerHousingEnter.denied()], state}
    end
  end

  defp handle_operation(@op_enter_plot, reader, state) do
    character_id = state.session_data[:character_id]

    case PacketReader.read_uint32(reader) do
      {:ok, plot_id, _reader} ->
        case HousingManager.enter_plot(character_id, plot_id) do
          {:ok, packets} ->
            {:ok, packets, state}

          {:error, :not_found} ->
            {:ok, [ServerHousingEnter.not_found()], state}

          {:error, :denied} ->
            {:ok, [ServerHousingEnter.denied()], state}
        end

      {:error, _} ->
        {:error, :invalid_packet}
    end
  end

  defp handle_operation(@op_exit, _reader, state) do
    character_id = state.session_data[:character_id]
    HousingManager.exit_plot(character_id)
    {:ok, [], state}
  end

  defp handle_operation(@op_decor_place, reader, state) do
    character_id = state.session_data[:character_id]

    with {:ok, plot_id} <- get_player_plot(character_id),
         true <- Housing.can_decorate?(plot_id, character_id),
         {:ok, attrs, _reader} <- read_decor_place_attrs(reader),
         {:ok, decor} <- Housing.place_decor(plot_id, attrs) do
      packet = ServerHousingDecorUpdate.placed(plot_id, decor)
      HousingManager.broadcast_to_plot(plot_id, packet)
      {:ok, [packet], state}
    else
      false ->
        {:ok, [], state}

      {:error, :not_in_plot} ->
        {:ok, [], state}

      {:error, reason} ->
        Logger.warning("Decor place failed: #{inspect(reason)}")
        {:ok, [], state}
    end
  end

  defp handle_operation(@op_decor_move, reader, state) do
    character_id = state.session_data[:character_id]

    with {:ok, plot_id} <- get_player_plot(character_id),
         true <- Housing.can_decorate?(plot_id, character_id),
         {:ok, decor_id, reader} <- PacketReader.read_uint32(reader),
         {:ok, attrs, _reader} <- read_decor_move_attrs(reader),
         {:ok, decor} <- Housing.move_decor(decor_id, attrs) do
      packet = ServerHousingDecorUpdate.moved(plot_id, decor)
      HousingManager.broadcast_to_plot(plot_id, packet)
      {:ok, [packet], state}
    else
      _ -> {:ok, [], state}
    end
  end

  defp handle_operation(@op_decor_remove, reader, state) do
    character_id = state.session_data[:character_id]

    with {:ok, plot_id} <- get_player_plot(character_id),
         true <- Housing.can_decorate?(plot_id, character_id),
         {:ok, decor_id, _reader} <- PacketReader.read_uint32(reader),
         :ok <- Housing.remove_decor(decor_id) do
      packet = ServerHousingDecorUpdate.removed(plot_id, decor_id)
      HousingManager.broadcast_to_plot(plot_id, packet)
      {:ok, [packet], state}
    else
      _ -> {:ok, [], state}
    end
  end

  defp handle_operation(@op_fabkit_install, reader, state) do
    character_id = state.session_data[:character_id]

    with {:ok, plot_id} <- get_player_plot(character_id),
         true <- Housing.can_decorate?(plot_id, character_id),
         {:ok, socket_index, reader} <- PacketReader.read_byte(reader),
         {:ok, fabkit_id, _reader} <- PacketReader.read_uint32(reader),
         {:ok, fabkit} <-
           Housing.install_fabkit(plot_id, %{socket_index: socket_index, fabkit_id: fabkit_id}) do
      packet = ServerHousingFabkitUpdate.installed(plot_id, fabkit)
      HousingManager.broadcast_to_plot(plot_id, packet)
      {:ok, [packet], state}
    else
      _ -> {:ok, [], state}
    end
  end

  defp handle_operation(@op_fabkit_remove, reader, state) do
    character_id = state.session_data[:character_id]

    with {:ok, plot_id} <- get_player_plot(character_id),
         true <- Housing.can_decorate?(plot_id, character_id),
         {:ok, fabkit_db_id, reader} <- PacketReader.read_uint32(reader),
         {:ok, socket_index, _reader} <- PacketReader.read_byte(reader),
         :ok <- Housing.remove_fabkit(fabkit_db_id) do
      packet = ServerHousingFabkitUpdate.removed(plot_id, fabkit_db_id, socket_index)
      HousingManager.broadcast_to_plot(plot_id, packet)
      {:ok, [packet], state}
    else
      _ -> {:ok, [], state}
    end
  end

  defp handle_operation(@op_neighbor_add, reader, state) do
    character_id = state.session_data[:character_id]

    with {:ok, plot} <- Housing.get_plot(character_id),
         {:ok, target_id, _reader} <- PacketReader.read_uint64(reader),
         {:ok, _neighbor} <- Housing.add_neighbor(plot.id, target_id) do
      # Send updated neighbor list to owner
      neighbors = Housing.list_neighbors(plot.id)
      packet = ServerHousingNeighborList.from_neighbor_list(plot.id, neighbors)
      {:ok, [packet], state}
    else
      _ -> {:ok, [], state}
    end
  end

  defp handle_operation(@op_neighbor_remove, reader, state) do
    character_id = state.session_data[:character_id]

    with {:ok, plot} <- Housing.get_plot(character_id),
         {:ok, target_id, _reader} <- PacketReader.read_uint64(reader),
         :ok <- Housing.remove_neighbor(plot.id, target_id) do
      neighbors = Housing.list_neighbors(plot.id)
      packet = ServerHousingNeighborList.from_neighbor_list(plot.id, neighbors)
      {:ok, [packet], state}
    else
      _ -> {:ok, [], state}
    end
  end

  defp handle_operation(@op_roommate_promote, reader, state) do
    character_id = state.session_data[:character_id]

    with {:ok, plot} <- Housing.get_plot(character_id),
         {:ok, target_id, _reader} <- PacketReader.read_uint64(reader),
         {:ok, _neighbor} <- Housing.promote_to_roommate(plot.id, target_id) do
      neighbors = Housing.list_neighbors(plot.id)
      packet = ServerHousingNeighborList.from_neighbor_list(plot.id, neighbors)
      {:ok, [packet], state}
    else
      _ -> {:ok, [], state}
    end
  end

  defp handle_operation(@op_roommate_demote, reader, state) do
    character_id = state.session_data[:character_id]

    with {:ok, plot} <- Housing.get_plot(character_id),
         {:ok, target_id, _reader} <- PacketReader.read_uint64(reader),
         {:ok, _neighbor} <- Housing.demote_from_roommate(plot.id, target_id) do
      neighbors = Housing.list_neighbors(plot.id)
      packet = ServerHousingNeighborList.from_neighbor_list(plot.id, neighbors)
      {:ok, [packet], state}
    else
      _ -> {:ok, [], state}
    end
  end

  defp handle_operation(op_type, _reader, _state) do
    Logger.warning("Unknown housing operation type: #{op_type}")
    {:error, :unknown_operation}
  end

  ## Helper Functions

  defp get_player_plot(character_id) do
    case HousingManager.get_player_location(character_id) do
      nil -> {:error, :not_in_plot}
      plot_id -> {:ok, plot_id}
    end
  end

  defp read_decor_place_attrs(reader) do
    with {:ok, decor_id, reader} <- PacketReader.read_uint32(reader),
         {:ok, pos_x, reader} <- PacketReader.read_float32(reader),
         {:ok, pos_y, reader} <- PacketReader.read_float32(reader),
         {:ok, pos_z, reader} <- PacketReader.read_float32(reader),
         {:ok, rot_pitch, reader} <- PacketReader.read_float32(reader),
         {:ok, rot_yaw, reader} <- PacketReader.read_float32(reader),
         {:ok, rot_roll, reader} <- PacketReader.read_float32(reader),
         {:ok, scale, reader} <- PacketReader.read_float32(reader),
         {:ok, is_exterior_byte, reader} <- PacketReader.read_byte(reader) do
      attrs = %{
        decor_id: decor_id,
        pos_x: pos_x,
        pos_y: pos_y,
        pos_z: pos_z,
        rot_pitch: rot_pitch,
        rot_yaw: rot_yaw,
        rot_roll: rot_roll,
        scale: scale,
        is_exterior: is_exterior_byte == 1
      }

      {:ok, attrs, reader}
    end
  end

  defp read_decor_move_attrs(reader) do
    with {:ok, pos_x, reader} <- PacketReader.read_float32(reader),
         {:ok, pos_y, reader} <- PacketReader.read_float32(reader),
         {:ok, pos_z, reader} <- PacketReader.read_float32(reader),
         {:ok, rot_pitch, reader} <- PacketReader.read_float32(reader),
         {:ok, rot_yaw, reader} <- PacketReader.read_float32(reader),
         {:ok, rot_roll, reader} <- PacketReader.read_float32(reader),
         {:ok, scale, reader} <- PacketReader.read_float32(reader) do
      attrs = %{
        pos_x: pos_x,
        pos_y: pos_y,
        pos_z: pos_z,
        rot_pitch: rot_pitch,
        rot_yaw: rot_yaw,
        rot_roll: rot_roll,
        scale: scale
      }

      {:ok, attrs, reader}
    end
  end
end
