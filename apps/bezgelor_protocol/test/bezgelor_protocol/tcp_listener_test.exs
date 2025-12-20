defmodule BezgelorProtocol.TcpListenerTest do
  use ExUnit.Case

  alias BezgelorProtocol.TcpListener

  @moduletag :capture_log

  describe "start_link/1" do
    test "starts TCP listener on specified port" do
      opts = [
        # Random available port
        port: 0,
        handler: BezgelorProtocol.Connection,
        name: :test_listener
      ]

      {:ok, _pid} = TcpListener.start_link(opts)

      # Verify we can get the port
      port = TcpListener.get_port(:test_listener)
      assert is_integer(port)
      assert port > 0

      # Clean up
      TcpListener.stop(:test_listener)
    end
  end
end
