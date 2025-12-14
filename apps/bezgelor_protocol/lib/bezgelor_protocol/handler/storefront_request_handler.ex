defmodule BezgelorProtocol.Handler.StorefrontRequestHandler do
  @moduledoc """
  Handles ClientStorefrontRequestCatalog packets (opcode 0x082D).

  The client sends this to request the store catalog. Per NexusForever, the server
  should respond with a sequence of packets:
  - 0x0988 - ServerStoreCategories
  - 0x098B - ServerStoreOffers
  - 0x0987 - ServerStoreFinalise

  These packets are required for the client to show the character select screen.
  """

  @behaviour BezgelorProtocol.Handler

  alias BezgelorProtocol.Packets.World.{
    ServerStoreCategories,
    ServerStoreOffers,
    ServerStoreFinalise
  }

  alias BezgelorProtocol.PacketWriter

  require Logger

  @impl true
  def handle(_payload, state) do
    Logger.debug("StorefrontRequestHandler: sending empty store catalog")

    # Build store packets
    categories = %ServerStoreCategories{categories: [], real_currency: 1}
    offers = %ServerStoreOffers{offer_groups: []}
    finalise = %ServerStoreFinalise{}

    # Send all packets as encrypted world packets
    responses = [
      {:server_store_categories, encode_packet(categories)},
      {:server_store_offers, encode_packet(offers)},
      {:server_store_finalise, encode_packet(finalise)}
    ]

    {:reply_multi_world_encrypted, responses, state}
  end

  defp encode_packet(%ServerStoreCategories{} = packet) do
    writer = PacketWriter.new()
    {:ok, writer} = ServerStoreCategories.write(packet, writer)
    PacketWriter.to_binary(writer)
  end

  defp encode_packet(%ServerStoreOffers{} = packet) do
    writer = PacketWriter.new()
    {:ok, writer} = ServerStoreOffers.write(packet, writer)
    PacketWriter.to_binary(writer)
  end

  defp encode_packet(%ServerStoreFinalise{} = packet) do
    writer = PacketWriter.new()
    {:ok, writer} = ServerStoreFinalise.write(packet, writer)
    PacketWriter.to_binary(writer)
  end
end
