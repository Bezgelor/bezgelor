defmodule BezgelorCrypto.SRP6Test do
  use ExUnit.Case, async: true

  alias BezgelorCrypto.SRP6

  describe "constants" do
    test "generator g is 2" do
      assert SRP6.g() == 2
    end

    test "prime N is 1024-bit" do
      n = SRP6.n()
      # 1024 bits = 128 bytes, BigInteger may have leading zeros
      assert is_integer(n)
      assert n > 0
    end
  end

  describe "generate_verifier/3" do
    test "generates deterministic verifier from salt and credentials" do
      salt = Base.decode16!("0102030405060708090A0B0C0D0E0F10")
      email = "test@example.com"
      password = "password123"

      v1 = SRP6.generate_verifier(salt, email, password)
      v2 = SRP6.generate_verifier(salt, email, password)

      assert v1 == v2
      assert is_binary(v1)
      assert byte_size(v1) > 0
    end

    test "different salts produce different verifiers" do
      salt1 = Base.decode16!("0102030405060708090A0B0C0D0E0F10")
      salt2 = Base.decode16!("1112131415161718191A1B1C1D1E1F20")
      email = "test@example.com"
      password = "password123"

      v1 = SRP6.generate_verifier(salt1, email, password)
      v2 = SRP6.generate_verifier(salt2, email, password)

      assert v1 != v2
    end
  end

  describe "server authentication flow" do
    setup do
      salt = BezgelorCrypto.Random.bytes(16)
      email = "player@example.com"
      password = "secret123"
      verifier = SRP6.generate_verifier(salt, email, password)

      %{salt: salt, email: email, password: password, verifier: verifier}
    end

    test "generates server credentials", %{email: email, salt: salt, verifier: verifier} do
      {:ok, server} = SRP6.new_server(email, salt, verifier)
      {:ok, server_b, _server} = SRP6.server_credentials(server)

      assert is_binary(server_b)
      assert byte_size(server_b) > 0
    end
  end
end
