defmodule BezgelorProtocol.Packets.World.ServerAccountCurrencySet do
  @moduledoc """
  Server packet containing account currencies (NCoins, etc).

  ## Overview

  Sent before the character list to inform the client of the account's
  currency balances.

  ## Packet Structure

  ```
  count      : uint32 (32 bits) - Number of currencies
  currencies : AccountCurrency[] - Currency entries
  ```

  ## AccountCurrency Structure

  ```
  type   : 5 bits  - Currency type ID
  amount : uint64  - Amount
  ```
  """

  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defmodule AccountCurrency do
    @moduledoc """
    An individual account currency entry.
    """
    defstruct type: 0,
              amount: 0

    @type t :: %__MODULE__{
            type: non_neg_integer(),
            amount: non_neg_integer()
          }
  end

  defstruct currencies: []

  @type t :: %__MODULE__{
          currencies: [AccountCurrency.t()]
        }

  @impl true
  def opcode, do: :server_account_currency_set

  @impl true
  @spec write(t(), PacketWriter.t()) :: {:ok, PacketWriter.t()}
  def write(%__MODULE__{} = packet, writer) do
    currencies = packet.currencies || []

    # Write count (32 bits)
    writer = PacketWriter.write_bits(writer, length(currencies), 32)

    # Write each currency
    writer =
      Enum.reduce(currencies, writer, fn curr, w ->
        w
        |> PacketWriter.write_bits(curr.type, 5)
        |> PacketWriter.write_bits(curr.amount, 64)
      end)

    writer = PacketWriter.flush_bits(writer)

    {:ok, writer}
  end
end
