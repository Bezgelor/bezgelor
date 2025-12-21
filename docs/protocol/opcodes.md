# WildStar Protocol Opcodes

This document describes the opcodes used in the WildStar game protocol, derived from NexusForever and client observation.

## Overview

Opcodes are 16-bit identifiers sent at the start of each packet to identify the message type. The protocol uses different opcodes for different server types (Auth/STS, Realm, World).

## Server Types

| Server | Port | Description |
|--------|------|-------------|
| Auth (STS) | 6600 | Secure Token Service for login authentication |
| Realm | 23115 | Realm selection and character list |
| World | 24000 | Main game world server |

## Opcode Categories

### Authentication (STS Server)

| Opcode | Hex | Direction | Name | Description |
|--------|-----|-----------|------|-------------|
| 0x0003 | 0003 | S→C | ServerHello | Initial server greeting |
| 0x0004 | 0004 | C→S | ClientHelloAuth | Client authentication request |
| 0x0005 | 0005 | S→C | ServerAuthAccepted | Authentication successful |
| 0x0006 | 0006 | S→C | ServerAuthDenied | Authentication failed |
| 0x0076 | 0076 | S→C | ServerAuthEncrypted | Encrypted auth packet |
| 0x0244 | 0244 | C→S | ClientEncrypted | Encrypted client packet |

### Realm Server

| Opcode | Hex | Direction | Name | Description |
|--------|-----|-----------|------|-------------|
| 0x0592 | 0592 | C→S | ClientHelloAuthRealm | Client hello to realm server |
| 0x0591 | 0591 | S→C | ServerAuthAcceptedRealm | Realm auth accepted |
| 0x063D | 063D | S→C | ServerAuthDeniedRealm | Realm auth denied |
| 0x0593 | 0593 | S→C | ServerRealmMessages | Realm server messages |
| 0x03DB | 03DB | S→C | ServerRealmInfo | Realm information |

### World Server - Connection

| Opcode | Hex | Direction | Name | Description |
|--------|-----|-----------|------|-------------|
| 0x058F | 058F | C→S | ClientHelloRealm | Client hello to world server |
| 0x03DC | 03DC | S→C | ServerRealmEncrypted | Encrypted world packet wrapper |
| 0x038C | 038C | C→S | ClientPackedWorld | Compressed/packed client packet |
| 0x025C | 025C | C→S | ClientPacked | Compressed client packet (no encryption) |
| 0x0241 | 0241 | C→S | ClientPregameKeepAlive | Pre-game keep-alive |

### World Server - Character

| Opcode | Hex | Direction | Name | Description |
|--------|-----|-----------|------|-------------|
| 0x07E0 | 07E0 | C→S | ClientCharacterList | Request character list |
| 0x0117 | 0117 | S→C | ServerCharacterList | Character list response |
| 0x07DD | 07DD | C→S | ClientCharacterSelect | Select character to play |
| 0x025B | 025B | C→S | ClientCharacterCreate | Create new character |
| 0x00DC | 00DC | S→C | ServerCharacterCreate | Character creation result |
| 0x0352 | 0352 | C→S | ClientCharacterDelete | Delete character |

### World Server - World Entry

| Opcode | Hex | Direction | Name | Description |
|--------|-----|-----------|------|-------------|
| 0x00F2 | 00F2 | C→S | ClientEnteredWorld | Client finished loading |
| 0x00AD | 00AD | S→C | ServerWorldEnter | Begin world entry (ServerChangeWorld in NF) |
| 0x00F1 | 00F1 | S→C | ServerInstanceSettings | Instance configuration |
| 0x0507 | 0507 | S→C | ServerHousingNeighbors | Housing neighbor list |
| 0x00FE | 00FE | S→C | ServerCharacterFlagsUpdated | Character flags update |
| 0x0262 | 0262 | S→C | ServerEntityCreate | Create entity in world |
| 0x0355 | 0355 | S→C | ServerEntityDestroy | Remove entity from world |
| 0x019B | 019B | S→C | ServerPlayerChanged | Player entity identification |
| 0x08B8 | 08B8 | S→C | ServerSetUnitPathType | Set unit path type |
| 0x06BC | 06BC | S→C | ServerPathInitialise | Initialize player path |
| 0x0845 | 0845 | S→C | ServerTimeOfDay | Current game time |
| 0x0636 | 0636 | S→C | ServerMovementControl | Movement control grant |
| 0x0061 | 0061 | S→C | ServerPlayerEnteredWorld | Player entry complete |

### World Server - Movement/Entity Commands

| Opcode | Hex | Direction | Name | Description |
|--------|-----|-----------|------|-------------|
| 0x0637 | 0637 | C→S | ClientEntityCommand | Entity movement commands |
| 0x063A | 063A | C→S | ClientZoneChange | Zone boundary crossed |
| 0x063B | 063B | C→S | ClientPlayerMovementSpeedUpdate | Speed change notification |
| 0x07F4 | 07F4 | C→S | ClientMovement | Legacy movement packet |
| 0x07F5 | 07F5 | S→C | ServerMovement | Movement broadcast |

### World Server - Account/Store

| Opcode | Hex | Direction | Name | Description |
|--------|-----|-----------|------|-------------|
| 0x0036 | 0036 | S→C | ServerMaxCharacterLevelAchieved | Max level achieved |
| 0x0966 | 0966 | S→C | ServerAccountCurrencySet | Account currency update |
| 0x0968 | 0968 | S→C | ServerAccountEntitlements | Account entitlements |
| 0x097F | 097F | S→C | ServerAccountTier | Account subscription tier |
| 0x0981 | 0981 | S→C | ServerGenericUnlockAccountList | Account unlocks |
| 0x0987 | 0987 | S→C | ServerStoreFinalise | Store loading complete |
| 0x0988 | 0988 | S→C | ServerStoreCategories | Store categories |
| 0x098B | 098B | S→C | ServerStoreOffers | Store item offers |
| 0x082D | 082D | C→S | ClientStorefrontRequestCatalog | Request store catalog |

### World Server - Settings/Options

| Opcode | Hex | Direction | Name | Description |
|--------|-----|-----------|------|-------------|
| 0x012B | 012B | C→S | ClientOptions | Client option change |

### World Server - Marketplace

| Opcode | Hex | Direction | Name | Description |
|--------|-----|-----------|------|-------------|
| 0x03EC | 03EC | C→S | ClientRequestOwnedCommodityOrders | Request commodity orders |
| 0x03ED | 03ED | C→S | ClientRequestOwnedItemAuctions | Request item auctions |

### World Server - Statistics/Telemetry

| Opcode | Hex | Direction | Name | Description |
|--------|-----|-----------|------|-------------|
| 0x023C | 023C | C→S | ClientStatisticsWatchdog | Watchdog telemetry |
| 0x023D | 023D | C→S | ClientStatisticsWindowOpen | Window open telemetry |
| 0x023E | 023E | C→S | ClientStatisticsGfx | Graphics telemetry |
| 0x023F | 023F | C→S | ClientStatisticsConnection | Connection telemetry |
| 0x0240 | 0240 | C→S | ClientStatisticsFramerate | Framerate telemetry |

## Unknown Opcodes

These opcodes have been observed from the client but are not documented in NexusForever:

| Opcode | Hex | Direction | Observation | Notes |
|--------|-----|-----------|-------------|-------|
| 0x0269 | 0269 | C→S | Sent after world entry | ~4 bytes payload, purpose unknown |
| 0x07CC | 07CC | C→S | Sent periodically | ~6 bytes payload, possibly heartbeat |
| 0x00D5 | 00D5 | C→S | After instance settings | Related to ServerInstanceSettings |
| 0x00DE | 00DE | C→S | Triggered on ability use | Not in NexusForever (gap 0x00DD→0x00E0), possibly dash/momentum |
| 0x00FB | 00FB | C→S | Occasional | Near path opcodes in enum, may be path-related |

### Investigation Status

- **0x0269**: No NexusForever handler, no documentation. Payload analysis needed.
- **0x07CC**: Sent frequently, likely client state. Does not appear in NexusForever.
- **0x00D5**: NexusForever comment mentions this with ServerInstanceSettings.
- **0x00DE**: Confirmed NOT in NexusForever GameMessageOpcode.cs (0x00DD→0x00E0 gap). Observed during ability use, possibly dash/sprint/momentum. Handler logs payloads for research.
- **0x00FB**: Near ServerPathExplorerPowerMapWaiting (0x00FA), may be path-related.

## EntityCommand Types

The ClientEntityCommand packet (0x0637) contains a list of movement commands:

| Value | Name | Description |
|-------|------|-------------|
| 0 | SetTime | Time synchronization |
| 1 | SetPlatform | Platform attachment |
| 2 | SetPosition | Position update |
| 3 | SetPositionKeys | Position keyframes |
| 4 | SetPositionPath | Path following |
| 5 | SetPositionSpline | Spline movement |
| 6 | SetPositionMultiSpline | Multi-spline movement |
| 7 | SetPositionProjectile | Projectile movement |
| 8 | SetVelocity | Velocity update |
| 9 | SetVelocityKeys | Velocity keyframes |
| 10 | SetVelocityDefaults | Reset velocity |
| 11 | SetMove | Movement state |
| 12 | SetMoveKeys | Movement keyframes |
| 13 | SetMoveDefaults | Reset movement |
| 14 | SetRotation | Rotation update |
| 15 | SetRotationKeys | Rotation keyframes |
| 16 | SetRotationSpline | Rotation spline |
| 17 | SetRotationMultiSpline | Multi-spline rotation |
| 18 | SetRotationFaceUnit | Face target unit |
| 19 | SetRotationFacePosition | Face position |
| 20 | SetRotationSpin | Spin rotation |
| 21 | SetRotationDefaults | Reset rotation |
| 22 | SetScale | Scale update |
| 23 | SetScaleKeys | Scale keyframes |
| 24 | SetState | State update |
| 25 | SetStateKeys | State keyframes |
| 26 | SetStateDefault | Reset state |
| 27 | SetMode | Mode update |
| 28 | SetModeKeys | Mode keyframes |

## References

- NexusForever: https://github.com/NexusForever/NexusForever
- GameMessageOpcode.cs: NexusForever.Network/Message/GameMessageOpcode.cs
