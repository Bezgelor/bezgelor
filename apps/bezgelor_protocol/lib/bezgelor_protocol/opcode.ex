defmodule BezgelorProtocol.Opcode do
  @moduledoc """
  WildStar game message opcodes.

  ## Overview

  Opcodes are 16-bit identifiers for packet types. This module provides
  bidirectional mapping between atom names and integer values.

  The opcodes are derived from NexusForever's GameMessageOpcode enum.
  We define only the opcodes we need, adding more as we implement handlers.

  ## Usage

      iex> Opcode.to_integer(:server_hello)
      3

      iex> Opcode.from_integer(0x0003)
      {:ok, :server_hello}
  """

  # Auth Server Opcodes
  @server_hello 0x0003
  @client_hello_auth 0x0004
  @server_auth_accepted 0x0005
  @server_auth_denied 0x0006
  @server_auth_encrypted 0x0076
  @client_encrypted 0x0077

  # World Server Opcodes
  @client_hello_realm 0x0008
  @server_realm_encrypted 0x0079
  @server_character_list 0x0117
  @client_character_select 0x0118
  @client_entered_world 0x00F2

  # Mapping from atom to integer
  @opcode_map %{
    # Auth
    server_hello: @server_hello,
    client_hello_auth: @client_hello_auth,
    server_auth_accepted: @server_auth_accepted,
    server_auth_denied: @server_auth_denied,
    server_auth_encrypted: @server_auth_encrypted,
    client_encrypted: @client_encrypted,
    # World
    client_hello_realm: @client_hello_realm,
    server_realm_encrypted: @server_realm_encrypted,
    server_character_list: @server_character_list,
    client_character_select: @client_character_select,
    client_entered_world: @client_entered_world
  }

  # Reverse mapping from integer to atom
  @reverse_map Map.new(@opcode_map, fn {k, v} -> {v, k} end)

  # Human-readable names
  @names %{
    server_hello: "ServerHello",
    client_hello_auth: "ClientHelloAuth",
    server_auth_accepted: "ServerAuthAccepted",
    server_auth_denied: "ServerAuthDenied",
    server_auth_encrypted: "ServerAuthEncrypted",
    client_encrypted: "ClientEncrypted",
    client_hello_realm: "ClientHelloRealm",
    server_realm_encrypted: "ServerRealmEncrypted",
    server_character_list: "ServerCharacterList",
    client_character_select: "ClientCharacterSelect",
    client_entered_world: "ClientEnteredWorld"
  }

  @type t :: atom()

  @doc "Convert opcode atom to integer value."
  @spec to_integer(t()) :: non_neg_integer()
  def to_integer(opcode) when is_atom(opcode) do
    Map.fetch!(@opcode_map, opcode)
  end

  @doc "Convert integer to opcode atom."
  @spec from_integer(non_neg_integer()) :: {:ok, t()} | {:error, :unknown_opcode}
  def from_integer(value) when is_integer(value) do
    case Map.fetch(@reverse_map, value) do
      {:ok, opcode} -> {:ok, opcode}
      :error -> {:error, :unknown_opcode}
    end
  end

  @doc "Get human-readable name for opcode."
  @spec name(t()) :: String.t()
  def name(opcode) when is_atom(opcode) do
    Map.get(@names, opcode, Atom.to_string(opcode))
  end

  @doc "List all known opcodes."
  @spec all() :: [t()]
  def all, do: Map.keys(@opcode_map)
end
