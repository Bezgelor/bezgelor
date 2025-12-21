# Documentation

Technical documentation for the Bezgelor WildStar server emulator.

## Core Documentation

| Document | Description |
|----------|-------------|
| [architecture.md](architecture.md) | Comprehensive guide to Bezgelor architecture for engineers including an Elixir/OTP primer |
| [status.md](status.md) | Project status tracking all implementation phases |
| [playability_gap_analysis.md](playability_gap_analysis.md) | Assessment of feature completeness and content coverage |

## System Implementation

| Document | Description |
|----------|-------------|
| [dev_capture_system.md](dev_capture_system.md) | Infrastructure for reverse engineering WildStar protocol via packet capture |
| [gear-visuals-system.md](gear-visuals-system.md) | How character gear is displayed and starting gear assigned |
| [loot_system_analysis.md](loot_system_analysis.md) | Investigation into extracting boss-specific loot data from client files |
| [llm-scripting-guide.md](llm-scripting-guide.md) | Guide for creating boss encounter scripts using LLM assistance |

## Protocol & Client

| Document | Description |
|----------|-------------|
| [protocol_deviations.md](protocol_deviations.md) | Intentional differences from NexusForever C# implementation |
| [bezgelor-vs-wildstar.md](bezgelor-vs-wildstar.md) | Intentional gameplay differences from original WildStar |
| [ability_bar_troubleshooting.md](ability_bar_troubleshooting.md) | Debugging empty or placeholder LAS slots |

## Deployment & Operations

| Document | Description |
|----------|-------------|
| [asset-extraction.md](asset-extraction.md) | Guide for extracting 3D models and textures from WildStar client |
| [portal_production_checklist.md](portal_production_checklist.md) | Production deployment checklist for the web portal |

## Milestone Reports

| Document | Description |
|----------|-------------|
| [2025-12-12-data-wiring-complete.md](2025-12-12-data-wiring-complete.md) | Milestone report: all client data wired to BezgelorData API |

## Subdirectories

| Directory | Description |
|-----------|-------------|
| [formats/](formats/) | WildStar file format specifications (M3 models, TEX textures) |
| [plans/](plans/) | Brainstorming sessions and implementation plans |
| [protocol/](protocol/) | WildStar protocol opcodes and packet documentation |
