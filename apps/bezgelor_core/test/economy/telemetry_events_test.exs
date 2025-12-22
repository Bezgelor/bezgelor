defmodule BezgelorCore.Economy.TelemetryEventsTest do
  use ExUnit.Case, async: true

  alias BezgelorCore.Economy.TelemetryEvents

  describe "event_names/0" do
    test "returns all economy event names" do
      event_names = TelemetryEvents.event_names()

      assert length(event_names) == 8

      assert [:bezgelor, :economy, :currency, :transaction] in event_names
      assert [:bezgelor, :economy, :vendor, :transaction] in event_names
      assert [:bezgelor, :economy, :loot, :drop] in event_names
      assert [:bezgelor, :economy, :auction, :event] in event_names
      assert [:bezgelor, :economy, :trade, :complete] in event_names
      assert [:bezgelor, :economy, :mail, :sent] in event_names
      assert [:bezgelor, :economy, :crafting, :complete] in event_names
      assert [:bezgelor, :economy, :repair, :complete] in event_names
    end
  end

  describe "emit_currency_transaction/1" do
    test "emits currency transaction event with correct structure" do
      # Attach a test handler
      :telemetry.attach(
        "test-currency-transaction",
        [:bezgelor, :economy, :currency, :transaction],
        fn event, measurements, metadata, _config ->
          send(self(), {:telemetry_event, event, measurements, metadata})
        end,
        nil
      )

      TelemetryEvents.emit_currency_transaction(
        amount: 100,
        balance_after: 1500,
        character_id: 42,
        currency_type: :credits,
        source_type: :quest,
        source_id: 123
      )

      assert_received {:telemetry_event, [:bezgelor, :economy, :currency, :transaction],
                       measurements, metadata}

      assert measurements.amount == 100
      assert measurements.balance_after == 1500
      assert measurements.duration_ms == 0

      assert metadata.character_id == 42
      assert metadata.currency_type == :credits
      assert metadata.source_type == :quest
      assert metadata.source_id == 123

      :telemetry.detach("test-currency-transaction")
    end

    test "accepts custom duration_ms" do
      :telemetry.attach(
        "test-currency-duration",
        [:bezgelor, :economy, :currency, :transaction],
        fn _event, measurements, _metadata, _config ->
          send(self(), {:duration, measurements.duration_ms})
        end,
        nil
      )

      TelemetryEvents.emit_currency_transaction(
        amount: 50,
        balance_after: 200,
        character_id: 1,
        currency_type: :omnibits,
        source_type: :vendor,
        source_id: 5,
        duration_ms: 150
      )

      assert_received {:duration, 150}

      :telemetry.detach("test-currency-duration")
    end
  end

  describe "emit_vendor_transaction/1" do
    test "emits vendor transaction event with correct structure" do
      :telemetry.attach(
        "test-vendor-transaction",
        [:bezgelor, :economy, :vendor, :transaction],
        fn event, measurements, metadata, _config ->
          send(self(), {:telemetry_event, event, measurements, metadata})
        end,
        nil
      )

      TelemetryEvents.emit_vendor_transaction(
        total_cost: 250,
        item_count: 5,
        character_id: 42,
        vendor_id: 101,
        transaction_type: :buy
      )

      assert_received {:telemetry_event, [:bezgelor, :economy, :vendor, :transaction],
                       measurements, metadata}

      assert measurements.total_cost == 250
      assert measurements.item_count == 5

      assert metadata.character_id == 42
      assert metadata.vendor_id == 101
      assert metadata.transaction_type == :buy

      :telemetry.detach("test-vendor-transaction")
    end
  end

  describe "emit_loot_drop/1" do
    test "emits loot drop event with correct structure" do
      :telemetry.attach(
        "test-loot-drop",
        [:bezgelor, :economy, :loot, :drop],
        fn event, measurements, metadata, _config ->
          send(self(), {:telemetry_event, event, measurements, metadata})
        end,
        nil
      )

      TelemetryEvents.emit_loot_drop(
        item_value: 50,
        currency_amount: 25,
        character_id: 42,
        creature_id: 200,
        world_id: 1,
        zone_id: 10
      )

      assert_received {:telemetry_event, [:bezgelor, :economy, :loot, :drop], measurements,
                       metadata}

      assert measurements.item_value == 50
      assert measurements.currency_amount == 25

      assert metadata.character_id == 42
      assert metadata.creature_id == 200
      assert metadata.world_id == 1
      assert metadata.zone_id == 10

      :telemetry.detach("test-loot-drop")
    end
  end

  describe "emit_auction_event/1" do
    test "emits auction event with correct structure" do
      :telemetry.attach(
        "test-auction-event",
        [:bezgelor, :economy, :auction, :event],
        fn event, measurements, metadata, _config ->
          send(self(), {:telemetry_event, event, measurements, metadata})
        end,
        nil
      )

      TelemetryEvents.emit_auction_event(
        price: 1000,
        fee: 50,
        character_id: 42,
        item_id: 301,
        event_type: :buyout
      )

      assert_received {:telemetry_event, [:bezgelor, :economy, :auction, :event], measurements,
                       metadata}

      assert measurements.price == 1000
      assert measurements.fee == 50

      assert metadata.character_id == 42
      assert metadata.item_id == 301
      assert metadata.event_type == :buyout

      :telemetry.detach("test-auction-event")
    end

    test "defaults fee to 0 when not provided" do
      :telemetry.attach(
        "test-auction-no-fee",
        [:bezgelor, :economy, :auction, :event],
        fn _event, measurements, _metadata, _config ->
          send(self(), {:fee, measurements.fee})
        end,
        nil
      )

      TelemetryEvents.emit_auction_event(
        price: 500,
        character_id: 1,
        item_id: 1,
        event_type: :list
      )

      assert_received {:fee, 0}

      :telemetry.detach("test-auction-no-fee")
    end
  end

  describe "emit_trade_complete/1" do
    test "emits trade complete event with correct structure" do
      :telemetry.attach(
        "test-trade-complete",
        [:bezgelor, :economy, :trade, :complete],
        fn event, measurements, metadata, _config ->
          send(self(), {:telemetry_event, event, measurements, metadata})
        end,
        nil
      )

      TelemetryEvents.emit_trade_complete(
        items_exchanged: 3,
        currency_exchanged: 500,
        initiator_id: 42,
        acceptor_id: 43
      )

      assert_received {:telemetry_event, [:bezgelor, :economy, :trade, :complete], measurements,
                       metadata}

      assert measurements.items_exchanged == 3
      assert measurements.currency_exchanged == 500

      assert metadata.initiator_id == 42
      assert metadata.acceptor_id == 43

      :telemetry.detach("test-trade-complete")
    end
  end

  describe "emit_mail_sent/1" do
    test "emits mail sent event with correct structure" do
      :telemetry.attach(
        "test-mail-sent",
        [:bezgelor, :economy, :mail, :sent],
        fn event, measurements, metadata, _config ->
          send(self(), {:telemetry_event, event, measurements, metadata})
        end,
        nil
      )

      TelemetryEvents.emit_mail_sent(
        currency_attached: 100,
        item_count: 2,
        cod_amount: 50,
        sender_id: 42,
        recipient_id: 43
      )

      assert_received {:telemetry_event, [:bezgelor, :economy, :mail, :sent], measurements,
                       metadata}

      assert measurements.currency_attached == 100
      assert measurements.item_count == 2
      assert measurements.cod_amount == 50

      assert metadata.sender_id == 42
      assert metadata.recipient_id == 43

      :telemetry.detach("test-mail-sent")
    end
  end

  describe "emit_crafting_complete/1" do
    test "emits crafting complete event with correct structure" do
      :telemetry.attach(
        "test-crafting-complete",
        [:bezgelor, :economy, :crafting, :complete],
        fn event, measurements, metadata, _config ->
          send(self(), {:telemetry_event, event, measurements, metadata})
        end,
        nil
      )

      TelemetryEvents.emit_crafting_complete(
        materials_cost: 200,
        result_value: 350,
        character_id: 42,
        schematic_id: 55,
        success: true
      )

      assert_received {:telemetry_event, [:bezgelor, :economy, :crafting, :complete],
                       measurements, metadata}

      assert measurements.materials_cost == 200
      assert measurements.result_value == 350

      assert metadata.character_id == 42
      assert metadata.schematic_id == 55
      assert metadata.success == true

      :telemetry.detach("test-crafting-complete")
    end
  end

  describe "emit_repair_complete/1" do
    test "emits repair complete event with correct structure" do
      :telemetry.attach(
        "test-repair-complete",
        [:bezgelor, :economy, :repair, :complete],
        fn event, measurements, metadata, _config ->
          send(self(), {:telemetry_event, event, measurements, metadata})
        end,
        nil
      )

      TelemetryEvents.emit_repair_complete(
        repair_cost: 75,
        items_repaired: 3,
        character_id: 42,
        vendor_id: 101
      )

      assert_received {:telemetry_event, [:bezgelor, :economy, :repair, :complete], measurements,
                       metadata}

      assert measurements.repair_cost == 75
      assert measurements.items_repaired == 3

      assert metadata.character_id == 42
      assert metadata.vendor_id == 101

      :telemetry.detach("test-repair-complete")
    end
  end
end
