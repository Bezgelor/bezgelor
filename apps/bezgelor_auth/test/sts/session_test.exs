defmodule BezgelorAuth.Sts.SessionTest do
  use ExUnit.Case, async: true

  alias BezgelorAuth.Sts.Session

  describe "new/0" do
    test "creates session in :none state" do
      session = Session.new()

      assert session.state == :none
      assert session.account == nil
      assert session.srp6_server == nil
      assert session.session_key == nil
      assert session.game_token == nil
    end
  end

  describe "connect/1" do
    test "transitions from :none to :connected" do
      session = Session.new()
      connected = Session.connect(session)

      assert connected.state == :connected
    end
  end

  describe "finish_login/1" do
    test "transitions to :authenticated and generates game token" do
      session = %Session{
        state: :login_start,
        account: %{id: 1, email: "test@example.com"},
        srp6_server: %{},
        session_key: "abc123"
      }

      {:ok, authenticated} = Session.finish_login(session)

      assert authenticated.state == :authenticated
      # Game token should be in GUID format
      assert authenticated.game_token =~ ~r/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/
    end
  end

  describe "get_game_token/1" do
    test "returns game token from session" do
      session = %Session{game_token: "test-token-123"}

      assert Session.get_game_token(session) == "test-token-123"
    end

    test "returns nil when no token" do
      session = Session.new()

      assert Session.get_game_token(session) == nil
    end
  end
end
