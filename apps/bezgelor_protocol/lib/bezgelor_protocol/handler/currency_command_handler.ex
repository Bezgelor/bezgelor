defmodule BezgelorProtocol.Handler.CurrencyCommandHandler do
  @moduledoc """
  Handler for /addcurrency and /addgold chat commands (GM commands).

  ## Usage

  In chat:
  - `/addcurrency <type> <amount>` - Add currency of specified type
  - `/ac <type> <amount>` - Alias for /addcurrency
  - `/addgold <amount>` - Add gold currency

  ## Currency Types

  - gold, elder_gems, renown, prestige, glory
  - crafting_vouchers, war_coins, shade_silver
  - protostar_promissory_notes

  ## Examples

      /addgold 1000         # Add 1000 gold
      /addcurrency gold 500 # Add 500 gold
      /ac elder_gems 10     # Add 10 elder gems
  """

  @compile {:no_warn_undefined, [BezgelorDb.Characters]}

  alias BezgelorDb.Characters

  require Logger

  @currency_types ~w(gold elder_gems renown prestige glory crafting_vouchers war_coins shade_silver protostar_promissory_notes)a

  @doc """
  Parse and execute addcurrency command.

  Returns {:ok, message, currency_type, new_amount} on success, or {:error, reason} on failure.
  The caller should send ServerCurrencyUpdate packet with the new amount.
  """
  @spec handle_addcurrency(String.t(), map()) ::
          {:ok, String.t(), atom(), non_neg_integer()} | {:error, atom() | String.t()}
  def handle_addcurrency(args, session) do
    character_id = get_in(session, [:session_data, :character, :id])

    unless character_id do
      {:error, "No character in session"}
    else
      args
      |> String.trim()
      |> String.split(~r/\s+/)
      |> parse_addcurrency_args()
      |> case do
        {:ok, currency_type, amount} ->
          do_addcurrency(character_id, currency_type, amount)

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc """
  Parse and execute addgold command (shortcut for /addcurrency gold).

  Returns {:ok, message, :gold, new_amount} on success, or {:error, reason} on failure.
  The caller should send ServerCurrencyUpdate packet with the new amount.
  """
  @spec handle_addgold(String.t(), map()) ::
          {:ok, String.t(), atom(), non_neg_integer()} | {:error, atom() | String.t()}
  def handle_addgold(args, session) do
    character_id = get_in(session, [:session_data, :character, :id])

    unless character_id do
      {:error, "No character in session"}
    else
      args
      |> String.trim()
      |> parse_amount()
      |> case do
        {:ok, amount} ->
          do_addcurrency(character_id, :gold, amount)

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  # Parse addcurrency arguments: <type> <amount>
  defp parse_addcurrency_args([type_str, amount_str]) do
    currency_type = parse_currency_type(type_str)

    if currency_type do
      case Integer.parse(amount_str) do
        {amount, ""} when amount != 0 -> {:ok, currency_type, amount}
        _ -> {:error, :invalid_amount}
      end
    else
      {:error, :invalid_currency_type}
    end
  end

  defp parse_addcurrency_args([]) do
    {:error, :missing_arguments}
  end

  defp parse_addcurrency_args([_]) do
    {:error, :missing_amount}
  end

  defp parse_addcurrency_args(_) do
    {:error, :invalid_arguments}
  end

  # Parse amount for addgold
  defp parse_amount(amount_str) do
    case Integer.parse(amount_str) do
      {amount, ""} when amount != 0 -> {:ok, amount}
      {amount, _rest} when amount != 0 -> {:ok, amount}
      _ -> {:error, :invalid_amount}
    end
  end

  # Parse currency type string to atom
  defp parse_currency_type(type_str) do
    atom =
      type_str
      |> String.downcase()
      |> String.to_existing_atom()

    if atom in @currency_types, do: atom, else: nil
  rescue
    ArgumentError -> nil
  end

  # Execute addcurrency
  defp do_addcurrency(character_id, currency_type, amount) do
    case Characters.add_currency(character_id, currency_type, amount) do
      {:ok, currency} ->
        new_amount = Map.get(currency, currency_type, 0)
        type_name = format_currency_name(currency_type)

        if amount > 0 do
          Logger.info(
            "GM: Added #{amount} #{type_name} to character #{character_id} (now #{new_amount})"
          )

          {:ok, "Added #{amount} #{type_name}. New balance: #{new_amount}", currency_type,
           new_amount}
        else
          Logger.info(
            "GM: Removed #{-amount} #{type_name} from character #{character_id} (now #{new_amount})"
          )

          {:ok, "Removed #{-amount} #{type_name}. New balance: #{new_amount}", currency_type,
           new_amount}
        end

      {:error, :insufficient_funds} ->
        {:error, "Insufficient funds to remove that amount"}

      {:error, reason} ->
        Logger.warning("GM addcurrency failed: #{inspect(reason)}")
        {:error, "Failed to modify currency: #{inspect(reason)}"}
    end
  end

  # Format currency type for display
  defp format_currency_name(type) do
    type
    |> Atom.to_string()
    |> String.replace("_", " ")
    |> String.split()
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  @doc """
  List available currency types.
  """
  @spec list_currency_types() :: [atom()]
  def list_currency_types, do: @currency_types
end
