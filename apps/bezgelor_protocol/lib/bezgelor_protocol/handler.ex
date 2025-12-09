defmodule BezgelorProtocol.Handler do
  @moduledoc """
  Behaviour for packet handlers.

  ## Overview

  Handlers process incoming packets and return updated connection state.
  Each handler receives the packet payload and current connection state.

  ## Example

      defmodule MyHandler do
        @behaviour BezgelorProtocol.Handler

        @impl true
        def handle(payload, state) do
          # Process the payload
          {:ok, state}
        end
      end

  ## Return Values

  - `{:ok, state}` - Success, continue with updated state
  - `{:reply, opcode, payload, state}` - Send a response packet
  - `{:error, reason}` - Error occurred, may disconnect
  """

  @doc """
  Handle an incoming packet.

  ## Parameters

  - `payload` - The raw packet payload (binary)
  - `state` - The current connection state

  ## Returns

  - `{:ok, state}` - Continue with updated state
  - `{:reply, opcode, payload, state}` - Send a response and continue
  - `{:error, reason}` - An error occurred
  """
  @callback handle(payload :: binary(), state :: map()) ::
              {:ok, map()}
              | {:reply, atom(), binary(), map()}
              | {:error, term()}
end
