defmodule BezgelorProtocol.Packets.Realm.ServerAuthDenied do
  @moduledoc """
  Server authentication denied response packet for realm server (port 23115).

  Sent when game token validation fails.

  ## Result Codes

  | Code | Atom | Description |
  |------|------|-------------|
  | 0 | :unknown | Unknown error |
  | 1 | :success | Success (shouldn't be in deny) |
  | 2 | :database_error | Database error |
  | 16 | :invalid_token | Invalid game token |
  | 18 | :no_realms_available | No realms available |
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
    no_realms_available: 18,
    version_mismatch: 19,
    account_banned: 20,
    account_suspended: 21
  }

  defstruct result: :unknown,
            error_value: 0,
            suspended_days: 0.0

  @type result ::
          :unknown
          | :success
          | :database_error
          | :invalid_token
          | :no_realms_available
          | :version_mismatch
          | :account_banned
          | :account_suspended

  @type t :: %__MODULE__{
          result: result(),
          error_value: non_neg_integer(),
          suspended_days: float()
        }

  @impl true
  def opcode, do: :server_auth_denied_realm

  @impl true
  @spec write(t(), PacketWriter.t()) :: {:ok, PacketWriter.t()}
  def write(%__MODULE__{} = packet, writer) do
    result_code = Map.fetch!(@result_codes, packet.result)

    writer =
      writer
      |> PacketWriter.write_u32(result_code)
      |> PacketWriter.write_u32(packet.error_value)
      |> PacketWriter.write_f32(packet.suspended_days)

    {:ok, writer}
  end

  @doc "Get the integer code for a result atom."
  @spec result_code(result()) :: non_neg_integer()
  def result_code(result), do: Map.fetch!(@result_codes, result)
end
