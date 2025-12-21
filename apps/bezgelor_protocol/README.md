# BezgelorProtocol

WildStar binary protocol implementation - packet parsing, serialization, framing, and handlers.

## Features

- Binary packet reading/writing with bit-level precision
- Opcode registry for all WildStar packets
- Handler behaviour for processing incoming packets
- TCP listener and connection management
- Support for both realm and world packet formats

## Key Modules

- `PacketReader` / `PacketWriter` - Bit-packed binary I/O
- `Opcode` - Packet type enumeration
- `Handler` - Behaviour for packet processors
- `Connection` - Client connection state machine

## Packet Implementation

Packets implement `Readable` and/or `Writable` behaviours:

```elixir
defmodule BezgelorProtocol.Packets.World.ServerEntityCreate do
  @behaviour BezgelorProtocol.Packet.Writable

  @impl true
  def opcode, do: :server_entity_create

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    writer
    |> PacketWriter.write_u32(packet.entity_id)
    |> PacketWriter.write_u64(packet.guid)
    |> PacketWriter.flush_bits()
  end
end
```
