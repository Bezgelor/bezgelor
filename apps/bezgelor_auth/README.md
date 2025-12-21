# BezgelorAuth

Authentication server (STS) for WildStar client connections. Handles initial client authentication using SRP6 protocol and issues session tokens for realm/world server access.

## Features

- SRP6 authentication protocol implementation
- Session token generation and validation
- TCP listener on port 6600
- Integration with BezgelorCrypto for cryptographic operations

## Usage

This application is part of the Bezgelor umbrella and starts automatically. Configure the listen port via environment variables or application config.

```elixir
# In config/config.exs
config :bezgelor_auth,
  port: 6600
```
