defmodule BezgelorProtocol.Handler.AuthHandlerTest do
  @moduledoc """
  Tests for AuthHandler packet processing.

  Tests use bit-packed wide string format for email.
  """
  # Cannot be async because it uses the database
  use ExUnit.Case, async: false

  import Bitwise

  alias BezgelorProtocol.Handler.AuthHandler
  alias BezgelorDb.Repo

  @moduletag :database

  setup do
    # Checkout a connection for this test
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
    :ok
  end

  describe "handle/2" do
    test "rejects invalid build version" do
      # Build packet with wrong build version
      payload = build_client_hello_auth(99999, "test@example.com")

      state = %{session_data: %{}}
      result = AuthHandler.handle(payload, state)

      assert {:reply, :server_auth_denied, response_payload, _state} = result

      # Parse the denial response
      <<result_code::little-32, _error::little-32, _days::little-float-32>> = response_payload
      # Result code 19 = version_mismatch
      assert result_code == 19
    end

    test "accepts correct build version and parses packet" do
      payload = build_client_hello_auth(16042, "test@example.com")

      state = %{session_data: %{}}
      result = AuthHandler.handle(payload, state)

      # Without an account, it should deny with account_not_found (code 16)
      assert {:reply, :server_auth_denied, response_payload, _state} = result

      <<result_code::little-32, _error::little-32, _days::little-float-32>> = response_payload
      # Result code 16 = invalid_token (used for account not found)
      assert result_code == 16
    end

    test "preserves session state" do
      payload = build_client_hello_auth(16042, "test@example.com")

      initial_state = %{session_data: %{some_key: "some_value"}}
      {:reply, _, _, result_state} = AuthHandler.handle(payload, initial_state)

      # The state should be preserved or updated, not lost
      assert is_map(result_state.session_data)
    end

    test "stores email in session data after parsing" do
      payload = build_client_hello_auth(16042, "user@test.com")

      state = %{session_data: %{}}
      {:reply, _, _, result_state} = AuthHandler.handle(payload, state)

      # Email should be stored in session for later use
      assert result_state.session_data[:email] == "user@test.com"
    end
  end

  # Build a ClientHelloAuth packet payload using bit-packed wide string
  defp build_client_hello_auth(build, email) do
    client_key_a = :crypto.strong_rand_bytes(128)
    client_proof_m1 = :crypto.strong_rand_bytes(32)

    <<
      build::little-32,
      build_wide_string(email)::binary,
      client_key_a::binary-size(128),
      client_proof_m1::binary-size(32)
    >>
  end

  # Build a bit-packed wide string matching NexusForever format
  defp build_wide_string("") do
    <<0::8>>
  end

  defp build_wide_string(string) when is_binary(string) do
    length = String.length(string)
    utf16_data = :unicode.characters_to_binary(string, :utf8, {:utf16, :little})

    if length < 128 do
      header = (length <<< 1) ||| 0
      <<header::8>> <> utf16_data
    else
      header = (length <<< 1) ||| 1
      <<header::16-little>> <> utf16_data
    end
  end
end
