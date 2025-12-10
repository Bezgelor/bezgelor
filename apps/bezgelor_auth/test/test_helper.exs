# Don't start the application during tests
Application.put_env(:bezgelor_auth, :start_server, false)

ExUnit.start()
