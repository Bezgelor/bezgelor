defmodule BezgelorCrypto.PacketCryptTest do
  use ExUnit.Case, async: true

  alias BezgelorCrypto.PacketCrypt

  describe "new/1" do
    test "creates a packet crypt with key" do
      crypt = PacketCrypt.new(12345)
      assert is_struct(crypt, PacketCrypt)
    end
  end

  describe "encrypt/decrypt round-trip" do
    test "decrypting encrypted data returns original" do
      crypt = PacketCrypt.new(0xDEADBEEF)
      original = "Hello, WildStar!"

      encrypted = PacketCrypt.encrypt(crypt, original)
      decrypted = PacketCrypt.decrypt(crypt, encrypted)

      assert decrypted == original
    end

    test "encrypted data differs from original" do
      crypt = PacketCrypt.new(0xDEADBEEF)
      original = "Secret message"

      encrypted = PacketCrypt.encrypt(crypt, original)
      assert encrypted != original
    end
  end

  describe "key_from_auth_build/0" do
    test "returns consistent key for build 16042" do
      key = PacketCrypt.key_from_auth_build()
      assert is_integer(key)
      assert key > 0
    end
  end

  describe "key_from_ticket/1" do
    test "generates key from 16-byte session key" do
      session_key = :crypto.strong_rand_bytes(16)
      key = PacketCrypt.key_from_ticket(session_key)

      assert is_integer(key)
      assert key > 0
    end

    test "raises for invalid session key length" do
      assert_raise ArgumentError, fn ->
        PacketCrypt.key_from_ticket(<<1, 2, 3>>)
      end
    end
  end
end
