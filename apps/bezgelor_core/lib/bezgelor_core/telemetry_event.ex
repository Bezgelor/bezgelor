defmodule BezgelorCore.TelemetryEvent do
  @moduledoc """
  Defines the structure for telemetry event declarations.

  ## Usage

  Add `@telemetry_events` attribute to modules that emit telemetry:

      @telemetry_events [
        %{
          event: [:bezgelor, :auth, :login],
          measurements: [:duration_ms],
          tags: [:account_id, :success],
          description: "User login attempt",
          domain: :auth
        }
      ]

  Then use the mix task to discover and generate metrics config.
  """

  @type t :: %{
          event: [atom()],
          measurements: [atom()],
          tags: [atom()],
          description: String.t(),
          domain: atom()
        }

  @required_keys [:event, :measurements, :tags, :description, :domain]

  @doc "Validate an event definition map."
  @spec validate(map()) :: :ok | {:error, String.t()}
  def validate(event) when is_map(event) do
    with :ok <- validate_required_keys(event),
         :ok <- validate_event_format(event.event),
         :ok <- validate_list_of_atoms(event.measurements, "measurements"),
         :ok <- validate_list_of_atoms(event.tags, "tags"),
         :ok <- validate_string(event.description, "description"),
         :ok <- validate_atom(event.domain, "domain") do
      :ok
    end
  end

  defp validate_required_keys(event) do
    missing = @required_keys -- Map.keys(event)

    case missing do
      [] -> :ok
      [key | _] -> {:error, "missing required key: #{key}"}
    end
  end

  defp validate_event_format(event) when is_list(event) do
    if Enum.all?(event, &is_atom/1) do
      :ok
    else
      {:error, "event must be a list of atoms"}
    end
  end

  defp validate_event_format(_), do: {:error, "event must be a list of atoms"}

  defp validate_list_of_atoms(list, name) when is_list(list) do
    if Enum.all?(list, &is_atom/1) do
      :ok
    else
      {:error, "#{name} must be a list of atoms"}
    end
  end

  defp validate_list_of_atoms(_, name), do: {:error, "#{name} must be a list"}

  defp validate_string(value, _name) when is_binary(value), do: :ok
  defp validate_string(_, name), do: {:error, "#{name} must be a string"}

  defp validate_atom(value, _name) when is_atom(value), do: :ok
  defp validate_atom(_, name), do: {:error, "#{name} must be an atom"}

  @doc """
  Convert an event definition to a telemetry_metrics metric definition.

  Returns a list of struct-like maps that can be used with Telemetry.Metrics.
  """
  @spec to_metric_def(t(), :summary | :counter | :last_value | :sum) :: [map()]
  def to_metric_def(event, metric_type \\ :summary) do
    event_name = Enum.join(event.event, ".")

    for measurement <- event.measurements do
      %{
        type: metric_type,
        name: "#{event_name}.#{measurement}",
        event_name: event.event,
        measurement: measurement,
        tags: event.tags,
        description: event.description,
        domain: event.domain
      }
    end
  end

  @doc "Get the event name as a dot-separated string."
  @spec event_name(t()) :: String.t()
  def event_name(event) do
    Enum.join(event.event, ".")
  end
end
