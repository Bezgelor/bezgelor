defmodule BezgelorProtocol.Packets.ServerAuthDenied do
  @moduledoc """
  Server authentication denied response packet.

  Sent when client authentication fails.

  ## Fields

  - `result` - Login result code (atom mapped to uint32)
  - `error_value` - Additional error code
  - `suspended_days` - Days remaining if account is suspended

  ## Result Codes

  | Code | Atom | Description |
  |------|------|-------------|
  | 0 | :unknown | Unknown error |
  | 1 | :success | Success (shouldn't be in deny) |
  | 2 | :database_error | Database error |
  | 16 | :invalid_token | Invalid game token |
  | 19 | :version_mismatch | Client/server version mismatch |
  | 20 | :account_banned | Account permanently banned |
  | 21 | :account_suspended | Account temporarily suspended |

  ## Wire Format

  ```
  result:          uint32 (little-endian)
  error_value:     uint32 (little-endian)
  suspended_days:  float32 (little-endian)
  ```
  """

  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  @result_codes %{
    unknown: 0,
    success: 1,
    database_error: 2,
    invalid_token: 16,
    version_mismatch: 19,
    account_banned: 20,
    account_suspended: 21
  }

  defstruct [
    :result,
    :error_value,
    :suspended_days
  ]

  @type result ::
          :unknown
          | :success
          | :database_error
          | :invalid_token
          | :version_mismatch
          | :account_banned
          | :account_suspended

  @type t :: %__MODULE__{
          result: result(),
          error_value: non_neg_integer(),
          suspended_days: float()
        }

  @impl true
  def opcode, do: :server_auth_denied

  @impl true
  @spec write(t(), PacketWriter.t()) :: {:ok, PacketWriter.t()}
  def write(%__MODULE__{} = packet, writer) do
    result_code = Map.fetch!(@result_codes, packet.result)

    writer =
      writer
      |> PacketWriter.write_uint32(result_code)
      |> PacketWriter.write_uint32(packet.error_value)
      |> PacketWriter.write_float32(packet.suspended_days)

    {:ok, writer}
  end

  @doc "Get the integer code for a result atom."
  @spec result_code(result()) :: non_neg_integer()
  def result_code(result), do: Map.fetch!(@result_codes, result)
end
