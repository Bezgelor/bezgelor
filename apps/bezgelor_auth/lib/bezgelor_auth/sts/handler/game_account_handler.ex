defmodule BezgelorAuth.Sts.Handler.GameAccountHandler do
  @moduledoc """
  Handler for /GameAccount/* endpoints.
  """

  alias BezgelorAuth.Sts.{Packet, Session}

  @doc """
  Handle /GameAccount/ListMyAccounts

  Returns the list of game accounts (characters) for the authenticated user.
  """
  @spec handle_list_accounts(Packet.t(), Session.t()) :: {:ok, binary(), Session.t()} | {:error, integer(), String.t(), Session.t()}
  def handle_list_accounts(_packet, session) do
    if session.state != :authenticated do
      {:error, 401, "Unauthorized", session}
    else
      account = session.account

      # Return a single game account entry (format matches NexusForever)
      response =
        "<Reply type=\"array\">\n<GameAccount>\n<Alias>#{account.email}</Alias>\n<Created></Created>\n<GameAccountId></GameAccountId>\n</GameAccount>\n</Reply>"

      {:ok, response, session}
    end
  end
end
