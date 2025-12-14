defmodule BezgelorAuth.Sts.Handler.StsHandler do
  @moduledoc """
  Handler for /Sts/* endpoints.
  """

  alias BezgelorAuth.Sts.{Packet, Session}

  @doc """
  Handle /Sts/Connect - Initial connection handshake.

  Note: NexusForever doesn't send a response for this endpoint - it just
  transitions the session state. The client proceeds to /Auth/LoginStart.
  """
  @spec handle_connect(Packet.t(), Session.t()) :: {:no_response, Session.t()}
  def handle_connect(_packet, session) do
    new_session = Session.connect(session)
    {:no_response, new_session}
  end

  @doc """
  Handle /Sts/Ping - Heartbeat.
  """
  @spec handle_ping(Packet.t(), Session.t()) :: {:ok, binary(), Session.t()}
  def handle_ping(_packet, session) do
    {:ok, "", session}
  end
end
