# BezgelorCrypto

Cryptographic primitives for WildStar protocol security.

## Features

- SRP6 authentication protocol implementation
- Packet encryption/decryption
- Password hashing and verification
- Session key generation

## Usage

```elixir
# Password verification
BezgelorCrypto.Password.verify(password, stored_hash)

# SRP6 authentication
{:ok, session} = BezgelorCrypto.SRP6.server_init(username, verifier)
```

This module provides the security foundation used by auth, realm, and world servers.
