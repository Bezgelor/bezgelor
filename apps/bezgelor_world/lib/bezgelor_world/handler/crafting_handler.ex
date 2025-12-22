defmodule BezgelorWorld.Handler.CraftingHandler do
  @moduledoc """
  Handles coordinate-based crafting operations.

  ## Packets Handled
  - ClientCraftStart - Start a crafting session
  - ClientCraftAddAdditive - Add additive to current craft
  - ClientCraftFinalize - Complete the craft
  - ClientCraftCancel - Cancel the craft

  ## Packets Sent
  - ServerCraftSession - Session state update
  - ServerCraftResult - Craft completion result
  - ServerTradeskillDiscovery - New variant discovered
  """

  @behaviour BezgelorProtocol.Handler

  require Logger

  alias BezgelorCore.Economy.TelemetryEvents
  alias BezgelorDb.Tradeskills
  alias BezgelorProtocol.PacketReader
  alias BezgelorProtocol.PacketWriter

  alias BezgelorProtocol.Packets.World.{
    ClientCraftStart,
    ClientCraftAddAdditive,
    ClientCraftFinalize,
    ClientCraftCancel,
    ServerCraftSession,
    ServerCraftResult,
    ServerTradeskillUpdate
  }

  alias BezgelorData.Store
  alias BezgelorWorld.Crafting.{CraftingSession, CoordinateSystem}

  @impl true
  def handle(payload, state) do
    reader = PacketReader.new(payload)

    with {:error, _} <- try_start(reader, state),
         {:error, _} <- try_add_additive(reader, state),
         {:error, _} <- try_finalize(reader, state),
         {:error, _} <- try_cancel(reader, state) do
      {:error, :unknown_crafting_packet}
    end
  end

  # Start crafting session

  defp try_start(reader, state) do
    case ClientCraftStart.read(reader) do
      {:ok, packet, _} -> handle_start(packet, state)
      error -> error
    end
  end

  defp handle_start(packet, state) do
    character_id = state.session_data[:character_id]

    # TODO: Validate schematic is known
    # TODO: Validate materials available
    # TODO: Validate crafting station if required

    session = CraftingSession.new(packet.schematic_id)

    new_state = put_in(state, [:session_data, :crafting_session], session)

    Logger.debug("Character #{character_id} started crafting schematic #{packet.schematic_id}")

    response = build_session_packet(session)
    send_packet(response, :server_craft_session, new_state)
  end

  # Add additive

  defp try_add_additive(reader, state) do
    case ClientCraftAddAdditive.read(reader) do
      {:ok, packet, _} -> handle_add_additive(packet, state)
      error -> error
    end
  end

  defp handle_add_additive(packet, state) do
    case get_in(state, [:session_data, :crafting_session]) do
      nil ->
        Logger.warning("Received additive without active craft session")
        {:ok, state}

      session ->
        character_id = state.session_data[:character_id]

        # TODO: Validate player has the additive items
        # TODO: Get additive vector from static data

        # Placeholder additive vector - real impl would lookup from static data
        additive = %{
          item_id: packet.item_id,
          quantity: packet.quantity,
          # Would come from static data
          vector_x: 10.0,
          vector_y: 5.0
        }

        session =
          session
          |> CraftingSession.set_overcharge(packet.overcharge_level)
          |> CraftingSession.add_additive(additive)

        new_state = put_in(state, [:session_data, :crafting_session], session)

        Logger.debug(
          "Character #{character_id} added additive #{packet.item_id} (overcharge: #{packet.overcharge_level})"
        )

        response = build_session_packet(session)
        send_packet(response, :server_craft_session, new_state)
    end
  end

  # Finalize craft

  defp try_finalize(reader, state) do
    case ClientCraftFinalize.read(reader) do
      {:ok, _packet, _} -> handle_finalize(state)
      error -> error
    end
  end

  defp handle_finalize(state) do
    case get_in(state, [:session_data, :crafting_session]) do
      nil ->
        Logger.warning("Received finalize without active craft session")
        {:ok, state}

      session ->
        character_id = state.session_data[:character_id]

        # Check for overcharge failure
        result =
          if CoordinateSystem.overcharge_failed?(session.overcharge_level) do
            build_failure_result()
          else
            # TODO: Get zones from static data for this schematic
            zones = get_schematic_zones(session.schematic_id)

            cursor = CraftingSession.get_cursor(session)
            {cursor_x, cursor_y} = cursor

            case CoordinateSystem.find_target_zone(cursor_x, cursor_y, zones) do
              {:ok, zone} ->
                build_success_result(session, zone, character_id)

              :no_zone ->
                build_failure_result()
            end
          end

        # Calculate materials cost and result value for telemetry
        materials_cost = calculate_materials_cost(session)
        result_value = if result.result in [:success, :critical], do: result.item_id, else: 0
        success = result.result in [:success, :critical]

        # Emit telemetry event
        TelemetryEvents.emit_crafting_complete(
          materials_cost: materials_cost,
          result_value: result_value,
          character_id: character_id,
          schematic_id: session.schematic_id,
          success: success
        )

        # Clear crafting session
        new_state = put_in(state, [:session_data, :crafting_session], nil)

        Logger.debug("Character #{character_id} finalized craft: #{result.result}")

        # Award XP if successful
        if result.result == :success or result.result == :critical do
          award_crafting_xp(character_id, session.schematic_id, result.xp_gained, new_state)
        end

        send_packet(result, :server_craft_result, new_state)
    end
  end

  # Cancel craft

  defp try_cancel(reader, state) do
    case ClientCraftCancel.read(reader) do
      {:ok, _packet, _} -> handle_cancel(state)
      error -> error
    end
  end

  defp handle_cancel(state) do
    character_id = state.session_data[:character_id]

    new_state = put_in(state, [:session_data, :crafting_session], nil)

    Logger.debug("Character #{character_id} cancelled craft")

    response = %ServerCraftResult{
      result: :cancelled,
      item_id: 0,
      quantity: 0,
      variant_id: 0,
      xp_gained: 0,
      quality: :standard
    }

    send_packet(response, :server_craft_result, new_state)
  end

  # Helpers

  defp build_session_packet(session) do
    additives =
      Enum.map(session.additives_used, fn add ->
        %{item_id: add.item_id, quantity: add.quantity}
      end)

    %ServerCraftSession{
      schematic_id: session.schematic_id,
      cursor_x: session.cursor_x,
      cursor_y: session.cursor_y,
      overcharge_level: session.overcharge_level,
      additives: additives
    }
  end

  defp build_failure_result do
    %ServerCraftResult{
      result: :failed,
      item_id: 0,
      quantity: 0,
      variant_id: 0,
      # Partial XP for attempt
      xp_gained: 50,
      quality: :standard
    }
  end

  defp build_success_result(session, zone, character_id) do
    # TODO: Get output item from schematic + variant
    # Placeholder
    output_item_id = 12345

    # Check for variant discovery
    variant_id = zone.variant_id

    if variant_id > 0 do
      Tradeskills.discover_schematic(character_id, session.schematic_id, variant_id)
    end

    %ServerCraftResult{
      result: if(zone.quality == :excellent, do: :critical, else: :success),
      item_id: output_item_id,
      quantity: 1,
      variant_id: variant_id,
      xp_gained: calculate_xp(zone.quality),
      quality: zone.quality
    }
  end

  defp calculate_xp(:poor), do: 100
  defp calculate_xp(:standard), do: 200
  defp calculate_xp(:good), do: 300
  defp calculate_xp(:excellent), do: 500
  defp calculate_xp(_), do: 100

  defp award_crafting_xp(character_id, _schematic_id, xp, _state) do
    # TODO: Look up profession from schematic
    # Placeholder
    profession_id = 1

    case Tradeskills.add_xp(character_id, profession_id, xp) do
      {:ok, tradeskill, levels_gained} when levels_gained > 0 ->
        # Send level up notification
        update = %ServerTradeskillUpdate{
          profession_id: tradeskill.profession_id,
          profession_type: tradeskill.profession_type,
          skill_level: tradeskill.skill_level,
          skill_xp: tradeskill.skill_xp,
          is_active: tradeskill.is_active,
          levels_gained: levels_gained
        }

        writer = PacketWriter.new()
        {:ok, writer} = ServerTradeskillUpdate.write(update, writer)
        packet_data = PacketWriter.to_binary(writer)

        send(self(), {:send_packet, :server_tradeskill_update, packet_data})

      _ ->
        :ok
    end
  end

  defp get_schematic_zones(schematic_id) do
    case Store.get_schematic(schematic_id) do
      {:ok, schematic} ->
        # Convert zones from static data, atomizing quality strings
        Enum.map(schematic.zones, fn zone ->
          %{
            id: zone.id,
            x_min: zone.x_min,
            x_max: zone.x_max,
            y_min: zone.y_min,
            y_max: zone.y_max,
            variant_id: zone.variant_id,
            quality: String.to_existing_atom(zone.quality)
          }
        end)

      :error ->
        # Fallback zones
        [
          %{id: 1, x_min: 0, x_max: 30, y_min: 0, y_max: 30, variant_id: 0, quality: :poor},
          %{id: 2, x_min: 35, x_max: 65, y_min: 35, y_max: 65, variant_id: 0, quality: :standard},
          %{
            id: 3,
            x_min: 70,
            x_max: 100,
            y_min: 70,
            y_max: 100,
            variant_id: 0,
            quality: :excellent
          }
        ]
    end
  end

  defp send_packet(packet, opcode, state) do
    writer = PacketWriter.new()
    {:ok, writer} = packet.__struct__.write(packet, writer)
    packet_data = PacketWriter.to_binary(writer)
    {:reply, opcode, packet_data, state}
  end

  defp calculate_materials_cost(session) do
    # Get the list of materials used from the session
    material_list = CraftingSession.get_material_cost(session)

    # Calculate total estimated cost
    # TODO: Look up actual item values from static data
    # For now, use placeholder calculation based on quantity
    Enum.reduce(material_list, 0, fn {_item_id, quantity}, acc ->
      # Placeholder: assume each material unit costs 10
      acc + quantity * 10
    end)
  end
end
