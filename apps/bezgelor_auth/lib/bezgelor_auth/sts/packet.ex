defmodule BezgelorAuth.Sts.Packet do
  @moduledoc """
  STS protocol packet parsing and building.

  The STS protocol is HTTP-like but uses `STS/1.0` as the protocol identifier.

  ## Request Format

      METHOD /Path STS/1.0\r\n
      l:123\r\n
      s:1\r\n
      \r\n
      <body>

  ## Response Format

      STS/1.0 200 OK\r\n
      l:123\r\n
      s:1R\r\n
      \r\n
      <body>

  Key headers:
  - `l` - Content length (required)
  - `s` - Sequence number (client sends number, server responds with numberR)
  """

  @protocol "STS/1.0"

  defstruct [
    :method,
    :uri,
    :protocol,
    :headers,
    :body,
    :status_code,
    :status_message
  ]

  @type t :: %__MODULE__{
          method: String.t() | nil,
          uri: String.t() | nil,
          protocol: String.t(),
          headers: map(),
          body: binary(),
          status_code: non_neg_integer() | nil,
          status_message: String.t() | nil
        }

  @doc """
  Parse a client STS request packet from binary data.

  Returns `{:ok, packet, remaining}` or `{:incomplete, data}` if more data needed.
  """
  @spec parse_request(binary()) ::
          {:ok, t(), binary()} | {:incomplete, binary()} | {:error, term()}
  def parse_request(data) do
    case parse_headers(data) do
      {:ok, request_line, headers, body_start, remaining} ->
        case parse_request_line(request_line) do
          {:ok, method, uri, protocol} ->
            content_length = get_content_length(headers)

            if byte_size(body_start <> remaining) >= content_length do
              body = binary_part(body_start <> remaining, 0, content_length)

              rest =
                binary_part(
                  body_start <> remaining,
                  content_length,
                  byte_size(body_start <> remaining) - content_length
                )

              packet = %__MODULE__{
                method: method,
                uri: uri,
                protocol: protocol,
                headers: headers,
                body: body
              }

              {:ok, packet, rest}
            else
              {:incomplete, data}
            end

          {:error, reason} ->
            {:error, reason}
        end

      {:incomplete, _} ->
        {:incomplete, data}
    end
  end

  @doc """
  Build a server STS response packet.
  """
  @spec build_response(non_neg_integer(), String.t(), map(), binary()) :: binary()
  def build_response(status_code, status_message, headers, body) do
    # NexusForever adds trailing newline to body
    body_with_newline = body <> "\n"

    # Add required headers (length includes trailing newline)
    headers =
      headers
      |> Map.put("l", Integer.to_string(byte_size(body_with_newline)))

    # Build header lines
    header_lines =
      Enum.map(headers, fn {k, v} -> "#{k}:#{v}" end)
      |> Enum.join("\r\n")

    # Build full response
    # Note: NexusForever uses double space before status message: "STS/1.0 200  OK"
    "#{@protocol} #{status_code}  #{status_message}\r\n#{header_lines}\r\n\r\n#{body_with_newline}"
  end

  @doc """
  Build an OK response with sequence number.
  """
  @spec ok_response(String.t(), binary()) :: binary()
  def ok_response(sequence, body) do
    build_response(200, "OK", %{"s" => "#{sequence}R"}, body)
  end

  @doc """
  Build an error response.

  For STS protocol, errors include an XML body with error code.
  The client uses these codes to display appropriate messages:
  - 3002: InvalidAccountNameOrPassword (shows "bad credentials" message)
  """
  @spec error_response(String.t(), non_neg_integer(), String.t()) :: binary()
  def error_response(sequence, status_code, message) do
    # Map HTTP status to STS error codes that the client understands
    error_code = sts_error_code(status_code, message)
    body = error_body(error_code)
    build_response(status_code, message, %{"s" => "#{sequence}R"}, body)
  end

  # STS Error codes (from NexusForever ErrorCode.cs)
  @error_invalid_credentials 3002

  defp sts_error_code(401, _message), do: @error_invalid_credentials
  defp sts_error_code(403, _message), do: @error_invalid_credentials
  defp sts_error_code(_status, _message), do: 0

  defp error_body(0), do: ""

  defp error_body(code) do
    # Format matches NexusForever ServerErrorMessage
    "<Error code=\"#{code}\" server=\"0\" module=\"0\" line=\"0\" text=\"0\"/>"
  end

  # Private functions

  defp parse_headers(data) do
    case :binary.split(data, "\r\n\r\n") do
      [header_section, body_and_rest] ->
        [request_line | header_lines] = String.split(header_section, "\r\n")

        headers =
          header_lines
          |> Enum.reduce(%{}, fn line, acc ->
            case String.split(line, ":", parts: 2) do
              [key, value] -> Map.put(acc, key, value)
              _ -> acc
            end
          end)

        {:ok, request_line, headers, body_and_rest, <<>>}

      [_incomplete] ->
        {:incomplete, data}
    end
  end

  defp parse_request_line(line) do
    case String.split(line, " ", parts: 3) do
      [method, uri, protocol] ->
        {:ok, method, uri, protocol}

      _ ->
        {:error, :invalid_request_line}
    end
  end

  defp get_content_length(headers) do
    case Map.get(headers, "l") do
      nil -> 0
      len -> String.to_integer(len)
    end
  end
end
