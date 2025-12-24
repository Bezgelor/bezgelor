defmodule BezgelorPortalWeb.Telemetry do
  use Supervisor
  import Telemetry.Metrics

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(_arg) do
    children = [
      # Telemetry poller will execute the given period measurements
      # every 10_000ms. Learn more here: https://hexdocs.pm/telemetry_metrics
      {:telemetry_poller, measurements: periodic_measurements(), period: 10_000}
      # Add reporters as children of your supervision tree.
      # {Telemetry.Metrics.ConsoleReporter, metrics: metrics()}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def metrics do
    [
      # Phoenix Metrics
      summary("phoenix.endpoint.start.system_time",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.endpoint.stop.duration",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.start.system_time",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.exception.duration",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.stop.duration",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.socket_connected.duration",
        unit: {:native, :millisecond}
      ),
      sum("phoenix.socket_drain.count"),
      summary("phoenix.channel_joined.duration",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.channel_handled_in.duration",
        tags: [:event],
        unit: {:native, :millisecond}
      ),

      # VM Metrics
      summary("vm.memory.total", unit: {:byte, :kilobyte}),
      summary("vm.total_run_queue_lengths.total"),
      summary("vm.total_run_queue_lengths.cpu"),
      summary("vm.total_run_queue_lengths.io"),

      # Client Connection Stats (from game client)
      summary("bezgelor.client.connection.rtt_ms",
        tags: [:character_name],
        unit: :millisecond,
        description: "Client round-trip time (ping)"
      ),
      summary("bezgelor.client.connection.bytes_received_per_sec",
        tags: [:character_name],
        unit: :byte,
        description: "Client network receive rate"
      ),
      summary("bezgelor.client.connection.bytes_sent_per_sec",
        tags: [:character_name],
        unit: :byte,
        description: "Client network send rate"
      ),
      last_value("bezgelor.client.connection.entity_count",
        tags: [:character_name],
        description: "Entities tracked by client"
      ),

      # Client Framerate Stats
      summary("bezgelor.client.framerate.recent_fps",
        tags: [:character_name],
        description: "Client recent average FPS"
      ),
      summary("bezgelor.client.framerate.session_fps",
        tags: [:character_name],
        description: "Client session average FPS"
      ),
      summary("bezgelor.client.framerate.highest_frame_time_us",
        tags: [:character_name],
        unit: :microsecond,
        description: "Slowest frame time (for detecting stutters)"
      ),

      # Client Watchdog Stats
      summary("bezgelor.client.watchdog.buffer_time_ms",
        tags: [:character_name],
        unit: :millisecond,
        description: "Client main loop buffer time (should be ~1000ms)"
      ),

      # Server Stats (from periodic poller)
      last_value("bezgelor.server.players.online",
        description: "Number of players currently online"
      ),
      last_value("bezgelor.server.creatures.spawned",
        description: "Number of creatures currently spawned"
      ),
      last_value("bezgelor.server.zones.active",
        description: "Number of zones with active players"
      ),

      # Game Telemetry Events
      counter("bezgelor.auth.login_complete.count",
        tags: [:success],
        description: "Login attempts"
      ),
      counter("bezgelor.realm.session_start.count",
        tags: [:success],
        description: "Realm session starts"
      ),
      counter("bezgelor.world.player_entered.count",
        tags: [:zone_id],
        description: "Players entering world"
      ),
      sum("bezgelor.combat.damage.damage_amount",
        tags: [:target_type],
        description: "Total damage dealt"
      ),
      counter("bezgelor.quest.accepted.count",
        description: "Quests accepted"
      ),
      counter("bezgelor.quest.completed.count",
        description: "Quests completed"
      ),
      counter("bezgelor.creature.killed.count",
        tags: [:zone_id],
        description: "Creatures killed"
      ),
      sum("bezgelor.creature.killed.xp_reward",
        description: "Total XP from kills"
      )
    ]
  end

  defp periodic_measurements do
    [
      # Server stats - these are measured every 10 seconds
      {__MODULE__, :measure_server_stats, []}
    ]
  end

  @doc false
  def measure_server_stats do
    # Get player count from WorldManager if available
    player_count =
      try do
        BezgelorWorld.WorldManager.session_count()
      rescue
        _ -> 0
      catch
        :exit, _ -> 0
      end

    # Get creature count across all world instances
    creature_count =
      try do
        BezgelorWorld.World.InstanceSupervisor.list_instances()
        |> Enum.reduce(0, fn {world_id, instance_id, _pid}, acc ->
          count = BezgelorWorld.World.Instance.creature_count({world_id, instance_id})
          acc + count
        end)
      rescue
        _ -> 0
      catch
        :exit, _ -> 0
      end

    # Get active zone count (list_worlds_with_players returns a MapSet)
    active_zones =
      try do
        BezgelorWorld.World.InstanceSupervisor.list_worlds_with_players()
        |> MapSet.size()
      rescue
        _ -> 0
      catch
        :exit, _ -> 0
      end

    :telemetry.execute(
      [:bezgelor, :server, :players],
      %{online: player_count},
      %{}
    )

    :telemetry.execute(
      [:bezgelor, :server, :creatures],
      %{spawned: creature_count},
      %{}
    )

    :telemetry.execute(
      [:bezgelor, :server, :zones],
      %{active: active_zones},
      %{}
    )
  end
end
