defmodule BezgelorCrypto.PasswordTest do
  use ExUnit.Case, async: true

  alias BezgelorCrypto.Password

  describe "generate_salt_and_verifier/2" do
    test "returns salt and verifier as hex strings" do
      {salt, verifier} = Password.generate_salt_and_verifier("test@example.com", "password123")

      assert is_binary(salt)
      assert is_binary(verifier)
      # Hex strings should be even length and contain only hex chars
      assert String.match?(salt, ~r/^[0-9A-F]+$/i)
      assert String.match?(verifier, ~r/^[0-9A-F]+$/i)
    end

    test "salt is 32 hex chars (16 bytes)" do
      {salt, _verifier} = Password.generate_salt_and_verifier("user@test.com", "secret")
      assert String.length(salt) == 32
    end

    test "generates different salt each time" do
      {salt1, _} = Password.generate_salt_and_verifier("user@test.com", "secret")
      {salt2, _} = Password.generate_salt_and_verifier("user@test.com", "secret")
      assert salt1 != salt2
    end

    test "email is case-insensitive" do
      salt = Base.decode16!("0102030405060708090A0B0C0D0E0F10")

      # Use same salt to compare verifiers
      v1 = BezgelorCrypto.SRP6.generate_verifier(salt, "TEST@EXAMPLE.COM", "password")
      v2 = BezgelorCrypto.SRP6.generate_verifier(salt, "test@example.com", "password")

      assert v1 == v2
    end
  end
end
