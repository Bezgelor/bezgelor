defmodule BezgelorProtocol.ConnectionTest do
  use ExUnit.Case

  alias BezgelorProtocol.{Connection, TcpListener, Framing, Opcode}

  @moduletag :capture_log

  describe "connection lifecycle" do
    setup do
      # Start a test listener
      opts = [
        port: 0,
        handler: Connection,
        name: :test_conn_listener,
        handler_opts: [connection_type: :auth]
      ]

      {:ok, _} = TcpListener.start_link(opts)
      port = TcpListener.get_port(:test_conn_listener)

      on_exit(fn ->
        TcpListener.stop(:test_conn_listener)
      end)

      %{port: port}
    end

    test "accepts connection and sends ServerHello", %{port: port} do
      # Connect to the server
      {:ok, socket} = :gen_tcp.connect(~c"localhost", port, [:binary, active: false])

      # Should receive ServerHello packet
      {:ok, data} = :gen_tcp.recv(socket, 0, 5000)

      # Parse the packet
      {:ok, [{opcode, _payload}], _} = Framing.parse_packets(data)

      assert opcode == Opcode.to_integer(:server_hello)

      :gen_tcp.close(socket)
    end
  end
end
