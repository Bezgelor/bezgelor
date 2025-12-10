defmodule BezgelorRealm do
  @moduledoc """
  Realm Server for WildStar authentication.

  Validates game tokens from STS server and provides realm selection.
  """

  @doc """
  Returns the configured port for the realm server.
  """
  @spec port() :: non_neg_integer()
  def port do
    Application.get_env(:bezgelor_realm, :port, 23115)
  end
end
