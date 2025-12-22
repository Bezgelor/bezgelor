defmodule BezgelorCore.Economy.TelemetryEvents do
  @moduledoc """
  Defines telemetry event specifications for the economy system.

  This module provides structured telemetry events for tracking all economy-related
  activities in the game, including currency transactions, vendor interactions,
  loot drops, auction house operations, player trades, mail, crafting, and repairs.

  ## Event Specifications

  ### Currency Transactions
  Event: `[:bezgelor, :economy, :currency, :transaction]`
  - Measurements: `%{amount: integer, balance_after: integer, duration_ms: integer}`
  - Metadata: `%{character_id: integer, currency_type: atom, source_type: atom, source_id: integer}`

  ### Vendor Transactions
  Event: `[:bezgelor, :economy, :vendor, :transaction]`
  - Measurements: `%{total_cost: integer, item_count: integer, duration_ms: integer}`
  - Metadata: `%{character_id: integer, vendor_id: integer, transaction_type: :buy | :sell}`

  ### Loot Drops
  Event: `[:bezgelor, :economy, :loot, :drop]`
  - Measurements: `%{item_value: integer, currency_amount: integer}`
  - Metadata: `%{character_id: integer, creature_id: integer, world_id: integer, zone_id: integer}`

  ### Auction House
  Event: `[:bezgelor, :economy, :auction, :event]`
  - Measurements: `%{price: integer, fee: integer}`
  - Metadata: `%{character_id: integer, item_id: integer, event_type: :list | :bid | :buyout | :expire | :cancel}`

  ### Player Trades
  Event: `[:bezgelor, :economy, :trade, :complete]`
  - Measurements: `%{items_exchanged: integer, currency_exchanged: integer, duration_ms: integer}`
  - Metadata: `%{initiator_id: integer, acceptor_id: integer}`

  ### Mail with Attachments
  Event: `[:bezgelor, :economy, :mail, :sent]`
  - Measurements: `%{currency_attached: integer, item_count: integer, cod_amount: integer}`
  - Metadata: `%{sender_id: integer, recipient_id: integer}`

  ### Crafting
  Event: `[:bezgelor, :economy, :crafting, :complete]`
  - Measurements: `%{materials_cost: integer, result_value: integer}`
  - Metadata: `%{character_id: integer, schematic_id: integer, success: boolean}`

  ### Item Repair
  Event: `[:bezgelor, :economy, :repair, :complete]`
  - Measurements: `%{repair_cost: integer, items_repaired: integer}`
  - Metadata: `%{character_id: integer, vendor_id: integer}`
  """

  @doc """
  Emits a currency transaction telemetry event.

  ## Parameters
  - `amount`: The amount of currency transferred (can be negative for deductions)
  - `balance_after`: The character's balance after the transaction
  - `character_id`: ID of the character involved
  - `currency_type`: Type of currency (e.g., :credits, :omnibits)
  - `source_type`: Type of source (e.g., :quest, :vendor, :loot)
  - `source_id`: ID of the source entity
  - `duration_ms`: Duration of the transaction in milliseconds (defaults to 0)

  ## Example

      emit_currency_transaction(
        amount: 100,
        balance_after: 1500,
        character_id: 42,
        currency_type: :credits,
        source_type: :quest,
        source_id: 123
      )
  """
  def emit_currency_transaction(opts) do
    measurements = %{
      amount: Keyword.fetch!(opts, :amount),
      balance_after: Keyword.fetch!(opts, :balance_after),
      duration_ms: Keyword.get(opts, :duration_ms, 0)
    }

    metadata = %{
      character_id: Keyword.fetch!(opts, :character_id),
      currency_type: Keyword.fetch!(opts, :currency_type),
      source_type: Keyword.fetch!(opts, :source_type),
      source_id: Keyword.fetch!(opts, :source_id)
    }

    :telemetry.execute([:bezgelor, :economy, :currency, :transaction], measurements, metadata)
  end

  @doc """
  Emits a vendor transaction telemetry event.

  ## Parameters
  - `total_cost`: Total cost of the transaction
  - `item_count`: Number of items involved
  - `character_id`: ID of the character involved
  - `vendor_id`: ID of the vendor
  - `transaction_type`: Type of transaction (:buy or :sell)
  - `duration_ms`: Duration of the transaction in milliseconds (defaults to 0)

  ## Example

      emit_vendor_transaction(
        total_cost: 250,
        item_count: 5,
        character_id: 42,
        vendor_id: 101,
        transaction_type: :buy
      )
  """
  def emit_vendor_transaction(opts) do
    measurements = %{
      total_cost: Keyword.fetch!(opts, :total_cost),
      item_count: Keyword.fetch!(opts, :item_count),
      duration_ms: Keyword.get(opts, :duration_ms, 0)
    }

    metadata = %{
      character_id: Keyword.fetch!(opts, :character_id),
      vendor_id: Keyword.fetch!(opts, :vendor_id),
      transaction_type: Keyword.fetch!(opts, :transaction_type)
    }

    :telemetry.execute([:bezgelor, :economy, :vendor, :transaction], measurements, metadata)
  end

  @doc """
  Emits a loot drop telemetry event.

  ## Parameters
  - `item_value`: Estimated value of the dropped item
  - `currency_amount`: Amount of currency dropped
  - `character_id`: ID of the character receiving the loot
  - `creature_id`: ID of the creature that dropped the loot
  - `world_id`: ID of the world where the drop occurred
  - `zone_id`: ID of the zone where the drop occurred

  ## Example

      emit_loot_drop(
        item_value: 50,
        currency_amount: 25,
        character_id: 42,
        creature_id: 200,
        world_id: 1,
        zone_id: 10
      )
  """
  def emit_loot_drop(opts) do
    measurements = %{
      item_value: Keyword.fetch!(opts, :item_value),
      currency_amount: Keyword.fetch!(opts, :currency_amount)
    }

    metadata = %{
      character_id: Keyword.fetch!(opts, :character_id),
      creature_id: Keyword.fetch!(opts, :creature_id),
      world_id: Keyword.fetch!(opts, :world_id),
      zone_id: Keyword.fetch!(opts, :zone_id)
    }

    :telemetry.execute([:bezgelor, :economy, :loot, :drop], measurements, metadata)
  end

  @doc """
  Emits an auction house event telemetry event.

  ## Parameters
  - `price`: Price of the item
  - `fee`: Auction house fee (if applicable)
  - `character_id`: ID of the character involved
  - `item_id`: ID of the item
  - `event_type`: Type of event (:list, :bid, :buyout, :expire, or :cancel)

  ## Example

      emit_auction_event(
        price: 1000,
        fee: 50,
        character_id: 42,
        item_id: 301,
        event_type: :buyout
      )
  """
  def emit_auction_event(opts) do
    measurements = %{
      price: Keyword.fetch!(opts, :price),
      fee: Keyword.get(opts, :fee, 0)
    }

    metadata = %{
      character_id: Keyword.fetch!(opts, :character_id),
      item_id: Keyword.fetch!(opts, :item_id),
      event_type: Keyword.fetch!(opts, :event_type)
    }

    :telemetry.execute([:bezgelor, :economy, :auction, :event], measurements, metadata)
  end

  @doc """
  Emits a player trade completion telemetry event.

  ## Parameters
  - `items_exchanged`: Number of items exchanged in the trade
  - `currency_exchanged`: Amount of currency exchanged
  - `initiator_id`: ID of the character who initiated the trade
  - `acceptor_id`: ID of the character who accepted the trade
  - `duration_ms`: Duration of the trade in milliseconds (defaults to 0)

  ## Example

      emit_trade_complete(
        items_exchanged: 3,
        currency_exchanged: 500,
        initiator_id: 42,
        acceptor_id: 43
      )
  """
  def emit_trade_complete(opts) do
    measurements = %{
      items_exchanged: Keyword.fetch!(opts, :items_exchanged),
      currency_exchanged: Keyword.fetch!(opts, :currency_exchanged),
      duration_ms: Keyword.get(opts, :duration_ms, 0)
    }

    metadata = %{
      initiator_id: Keyword.fetch!(opts, :initiator_id),
      acceptor_id: Keyword.fetch!(opts, :acceptor_id)
    }

    :telemetry.execute([:bezgelor, :economy, :trade, :complete], measurements, metadata)
  end

  @doc """
  Emits a mail sent telemetry event.

  ## Parameters
  - `currency_attached`: Amount of currency attached to the mail
  - `item_count`: Number of items attached
  - `cod_amount`: Cash on delivery amount (if applicable)
  - `sender_id`: ID of the sending character
  - `recipient_id`: ID of the receiving character

  ## Example

      emit_mail_sent(
        currency_attached: 100,
        item_count: 2,
        cod_amount: 0,
        sender_id: 42,
        recipient_id: 43
      )
  """
  def emit_mail_sent(opts) do
    measurements = %{
      currency_attached: Keyword.fetch!(opts, :currency_attached),
      item_count: Keyword.fetch!(opts, :item_count),
      cod_amount: Keyword.get(opts, :cod_amount, 0)
    }

    metadata = %{
      sender_id: Keyword.fetch!(opts, :sender_id),
      recipient_id: Keyword.fetch!(opts, :recipient_id)
    }

    :telemetry.execute([:bezgelor, :economy, :mail, :sent], measurements, metadata)
  end

  @doc """
  Emits a crafting completion telemetry event.

  ## Parameters
  - `materials_cost`: Estimated cost of materials used
  - `result_value`: Estimated value of the crafted item
  - `character_id`: ID of the crafting character
  - `schematic_id`: ID of the schematic used
  - `success`: Whether the crafting was successful

  ## Example

      emit_crafting_complete(
        materials_cost: 200,
        result_value: 350,
        character_id: 42,
        schematic_id: 55,
        success: true
      )
  """
  def emit_crafting_complete(opts) do
    measurements = %{
      materials_cost: Keyword.fetch!(opts, :materials_cost),
      result_value: Keyword.fetch!(opts, :result_value)
    }

    metadata = %{
      character_id: Keyword.fetch!(opts, :character_id),
      schematic_id: Keyword.fetch!(opts, :schematic_id),
      success: Keyword.fetch!(opts, :success)
    }

    :telemetry.execute([:bezgelor, :economy, :crafting, :complete], measurements, metadata)
  end

  @doc """
  Emits an item repair completion telemetry event.

  ## Parameters
  - `repair_cost`: Total cost of the repair
  - `items_repaired`: Number of items repaired
  - `character_id`: ID of the character getting repairs
  - `vendor_id`: ID of the vendor performing the repair

  ## Example

      emit_repair_complete(
        repair_cost: 75,
        items_repaired: 3,
        character_id: 42,
        vendor_id: 101
      )
  """
  def emit_repair_complete(opts) do
    measurements = %{
      repair_cost: Keyword.fetch!(opts, :repair_cost),
      items_repaired: Keyword.fetch!(opts, :items_repaired)
    }

    metadata = %{
      character_id: Keyword.fetch!(opts, :character_id),
      vendor_id: Keyword.fetch!(opts, :vendor_id)
    }

    :telemetry.execute([:bezgelor, :economy, :repair, :complete], measurements, metadata)
  end

  @doc """
  Returns a list of all economy telemetry event names.
  """
  def event_names do
    [
      [:bezgelor, :economy, :currency, :transaction],
      [:bezgelor, :economy, :vendor, :transaction],
      [:bezgelor, :economy, :loot, :drop],
      [:bezgelor, :economy, :auction, :event],
      [:bezgelor, :economy, :trade, :complete],
      [:bezgelor, :economy, :mail, :sent],
      [:bezgelor, :economy, :crafting, :complete],
      [:bezgelor, :economy, :repair, :complete]
    ]
  end
end
