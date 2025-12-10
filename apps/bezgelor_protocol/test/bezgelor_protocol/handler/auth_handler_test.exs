defmodule BezgelorProtocol.Handler.AuthHandlerTest do
  # Cannot be async because it uses the database
  use ExUnit.Case, async: false

  alias BezgelorProtocol.Handler.AuthHandler
  alias BezgelorDb.Repo

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

  # Build a ClientHelloAuth packet payload
  defp build_client_hello_auth(build, email) do
    client_key_a = :crypto.strong_rand_bytes(128)
    client_proof_m1 = :crypto.strong_rand_bytes(32)

    utf16_email = :unicode.characters_to_binary(email, :utf8, {:utf16, :little})
    email_length = String.length(email)

    <<
      build::little-32,
      email_length::little-32,
      utf16_email::binary,
      client_key_a::binary-size(128),
      client_proof_m1::binary-size(32)
    >>
  end
end
