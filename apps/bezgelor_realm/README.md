# BezgelorRealm

Realm server handling character selection and world server routing.

## Features

- Character list display
- Character creation/deletion
- Realm status and population tracking
- World server connection handoff
- TCP listener on port 23115

## Flow

1. Client authenticates via Auth server (BezgelorAuth)
2. Client connects to Realm server with session token
3. Player selects/creates character
4. Realm server provides world server connection details
