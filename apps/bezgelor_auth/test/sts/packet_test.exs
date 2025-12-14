defmodule BezgelorAuth.Sts.PacketTest do
  use ExUnit.Case, async: true

  alias BezgelorAuth.Sts.Packet

  describe "parse_request/1" do
    test "parses a valid STS request" do
      request = "POST /Sts/Connect STS/1.0\r\nl:0\r\ns:1\r\n\r\n"

      assert {:ok, packet, ""} = Packet.parse_request(request)
      assert packet.method == "POST"
      assert packet.uri == "/Sts/Connect"
      assert packet.protocol == "STS/1.0"
      assert packet.headers["l"] == "0"
      assert packet.headers["s"] == "1"
      assert packet.body == ""
    end

    test "parses request with body" do
      body = "<LoginName>test@example.com</LoginName>"
      request = "POST /Auth/LoginStart STS/1.0\r\nl:#{byte_size(body)}\r\ns:2\r\n\r\n#{body}"

      assert {:ok, packet, ""} = Packet.parse_request(request)
      assert packet.method == "POST"
      assert packet.uri == "/Auth/LoginStart"
      assert packet.body == body
    end

    test "returns incomplete for partial request" do
      partial = "POST /Sts/Connect STS/1.0\r\nl:0"

      assert {:incomplete, ^partial} = Packet.parse_request(partial)
    end

    test "handles remaining data after packet" do
      request = "POST /Sts/Connect STS/1.0\r\nl:0\r\ns:1\r\n\r\nPOST /Sts/Ping"

      assert {:ok, packet, remaining} = Packet.parse_request(request)
      assert packet.uri == "/Sts/Connect"
      assert remaining == "POST /Sts/Ping"
    end
  end

  describe "ok_response/2" do
    test "builds a valid OK response" do
      response = Packet.ok_response("1", "test body")

      assert response =~ "STS/1.0 200 OK\r\n"
      assert response =~ "l:9\r\n"
      assert response =~ "s:1R\r\n"
      assert response =~ "test body"
    end

    test "builds response with empty body" do
      response = Packet.ok_response("42", "")

      assert response =~ "STS/1.0 200 OK\r\n"
      assert response =~ "l:0\r\n"
      assert response =~ "s:42R\r\n"
    end
  end

  describe "error_response/3" do
    test "builds error response" do
      response = Packet.error_response("1", 400, "Bad Request")

      assert response =~ "STS/1.0 400 Bad Request\r\n"
      assert response =~ "s:1R\r\n"
    end

    test "builds 401 unauthorized response" do
      response = Packet.error_response("5", 401, "Unauthorized")

      assert response =~ "STS/1.0 401 Unauthorized\r\n"
      assert response =~ "s:5R\r\n"
    end
  end
end
