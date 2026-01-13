# Bezgelor Architecture Documentation

This directory contains C4-style architecture diagrams for the Bezgelor WildStar server emulator.

## Diagram Index

| Diagram | Level | Description |
|---------|-------|-------------|
| [System Context](c4-context.md) | L1 | External actors and systems |
| [Containers](c4-containers.md) | L2 | Umbrella apps and their relationships |
| [World Server Components](c4-world-components.md) | L3 | Internal structure of bezgelor_world |
| [Protocol Components](c4-protocol-components.md) | L3 | Network protocol handling |
| [Data Layer Components](c4-data-components.md) | L3 | Database and static data architecture |
| [Deployment](c4-deployment.md) | Deployment | Production infrastructure |

## C4 Model Overview

The C4 model provides hierarchical views of the system:

```
Level 1: System Context
    └── How Bezgelor fits in the broader ecosystem

Level 2: Containers
    └── High-level building blocks (umbrella apps)

Level 3: Components
    └── Internal structure of key containers

Deployment
    └── How the system runs in production
```

## Viewing the Diagrams

These diagrams use [Mermaid](https://mermaid.js.org/) syntax. They can be rendered:

1. **GitHub/GitLab**: Renders automatically in markdown preview
2. **VS Code**: Use the "Markdown Preview Mermaid Support" extension
3. **Mermaid Live**: Paste code at https://mermaid.live

## Quick Architecture Summary

```
┌─────────────────────────────────────────────────────────────┐
│                     WildStar Game Client                     │
└─────────────────────────────────────────────────────────────┘
                              │
        ┌─────────────────────┼─────────────────────┐
        │                     │                     │
        ▼                     ▼                     ▼
   ┌─────────┐         ┌───────────┐         ┌───────────┐
   │  Auth   │   ──►   │   Realm   │   ──►   │   World   │
   │  :6600  │         │  :23115   │         │  :24000   │
   └─────────┘         └───────────┘         └───────────┘
        │                     │                     │
        └─────────────────────┼─────────────────────┘
                              │
                    ┌─────────┴─────────┐
                    │                   │
                    ▼                   ▼
             ┌───────────┐       ┌───────────┐
             │ PostgreSQL│       │    ETS    │
             │   :5433   │       │ (Memory)  │
             └───────────┘       └───────────┘
              Persistent          Static Game
                 Data                Data
```

## Key Design Decisions

1. **Elixir Umbrella**: Modular codebase with clear boundaries
2. **OTP Supervision**: Fault-tolerant process architecture
3. **Message Passing**: No shared state between processes
4. **Context Pattern**: Domain-driven database access
5. **ETS for Static Data**: O(1) lookups for game data
6. **Per-Connection Process**: Each player isolated in their own process
7. **Per-World Process**: Each active world managed independently
