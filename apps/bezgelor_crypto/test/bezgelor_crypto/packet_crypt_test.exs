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

      assert {:ok, encrypted} = PacketCrypt.encrypt(crypt, original)
      assert {:ok, decrypted} = PacketCrypt.decrypt(crypt, encrypted)

      assert decrypted == original
    end

    test "encrypted data differs from original" do
      crypt = PacketCrypt.new(0xDEADBEEF)
      original = "Secret message"

      assert {:ok, encrypted} = PacketCrypt.encrypt(crypt, original)
      assert encrypted != original
    end

    test "handles empty buffer" do
      crypt = PacketCrypt.new(0xDEADBEEF)

      assert {:ok, encrypted} = PacketCrypt.encrypt(crypt, "")
      assert {:ok, decrypted} = PacketCrypt.decrypt(crypt, encrypted)
      assert decrypted == ""
    end

    test "handles large buffer" do
      crypt = PacketCrypt.new(0xDEADBEEF)
      original = :crypto.strong_rand_bytes(4096)

      assert {:ok, encrypted} = PacketCrypt.encrypt(crypt, original)
      assert {:ok, decrypted} = PacketCrypt.decrypt(crypt, encrypted)
      assert decrypted == original
    end
  end

  describe "error handling" do
    test "encrypt returns error for invalid cipher" do
      assert {:error, :invalid_cipher} = PacketCrypt.encrypt(nil, "data")
      assert {:error, :invalid_cipher} = PacketCrypt.encrypt("not_a_cipher", "data")
    end

    test "decrypt returns error for invalid cipher" do
      assert {:error, :invalid_cipher} = PacketCrypt.decrypt(nil, "data")
      assert {:error, :invalid_cipher} = PacketCrypt.decrypt("not_a_cipher", "data")
    end

    test "encrypt returns error for cipher with nil key" do
      invalid_crypt = %PacketCrypt{key: nil, key_value: 0}
      assert {:error, :invalid_key} = PacketCrypt.encrypt(invalid_crypt, "data")
    end

    test "decrypt returns error for cipher with nil key" do
      invalid_crypt = %PacketCrypt{key: nil, key_value: 0}
      assert {:error, :invalid_key} = PacketCrypt.decrypt(invalid_crypt, "data")
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
