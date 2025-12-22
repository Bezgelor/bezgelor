import { Chart, registerables } from 'chart.js'

// Register all Chart.js components
Chart.register(...registerables)

/**
 * ChartJS Hook
 *
 * Phoenix LiveView hook for Chart.js integration.
 *
 * Usage:
 *   <div id="my-chart"
 *        phx-hook="ChartJS"
 *        phx-update="ignore"
 *        data-chart-type="line"
 *        data-chart-config={@chart_config}>
 *     <canvas></canvas>
 *   </div>
 *
 * Data attributes:
 *   - data-chart-type: Chart type (line, bar, pie, doughnut, radar, polarArea, bubble, scatter)
 *   - data-chart-config: JSON string containing chart configuration
 *
 * Server-side example:
 *   # In your LiveView
 *   assign(socket, :chart_config, Jason.encode!(%{
 *     labels: ["Jan", "Feb", "Mar", "Apr", "May"],
 *     datasets: [%{
 *       label: "Players Online",
 *       data: [12, 19, 3, 5, 2],
 *       backgroundColor: "rgba(75, 192, 192, 0.2)",
 *       borderColor: "rgba(75, 192, 192, 1)",
 *       borderWidth: 1
 *     }]
 *   }))
 *
 * Push events from server:
 *   # Update chart data
 *   push_event(socket, "update-chart", %{
 *     id: "my-chart",
 *     data: %{
 *       labels: ["Jan", "Feb", "Mar"],
 *       datasets: [...]
 *     }
 *   })
 *
 *   # Update specific dataset
 *   push_event(socket, "update-chart", %{
 *     id: "my-chart",
 *     dataset_index: 0,
 *     data: [10, 20, 30]
 *   })
 *
 *   # Change chart type
 *   push_event(socket, "update-chart", %{
 *     id: "my-chart",
 *     type: "bar"
 *   })
 */
export const ChartJS = {
  mounted() {
    this.destroyed = false
    this.chartType = this.el.dataset.chartType || 'line'

    // Find or create canvas element
    let canvas = this.el.querySelector('canvas')
    if (!canvas) {
      canvas = document.createElement('canvas')
      this.el.appendChild(canvas)
    }

    // Parse chart configuration
    let config = {}
    try {
      config = JSON.parse(this.el.dataset.chartConfig || '{}')
    } catch (e) {
      console.warn('[ChartJS] Failed to parse chart config:', e)
      config = {}
    }

    // Create the chart
    this._createChart(canvas, this.chartType, config)

    // Listen for update events from LiveView
    this.handleEvent("update-chart", (payload) => {
      // Only handle events for this chart
      if (payload.id && payload.id !== this.el.id) {
        return
      }

      this._updateChart(payload)
    })

    // Handle responsive resize
    this.resizeObserver = new ResizeObserver(() => {
      if (this.chart) {
        this.chart.resize()
      }
    })
    this.resizeObserver.observe(this.el)
  },

  updated() {
    // Re-parse config if it changed
    const chartType = this.el.dataset.chartType || 'line'
    let config = {}
    try {
      config = JSON.parse(this.el.dataset.chartConfig || '{}')
    } catch (e) {
      console.warn('[ChartJS] Failed to parse chart config:', e)
      return
    }

    // If chart type changed, recreate the chart
    if (chartType !== this.chartType) {
      this.chartType = chartType
      const canvas = this.el.querySelector('canvas')
      this._destroyChart()
      this._createChart(canvas, chartType, config)
    } else {
      // Otherwise, update the existing chart
      this._updateChartData(config)
    }
  },

  destroyed() {
    this.destroyed = true

    if (this.resizeObserver) {
      this.resizeObserver.disconnect()
      this.resizeObserver = null
    }

    this._destroyChart()
  },

  /**
   * Create a new Chart.js instance
   * @private
   */
  _createChart(canvas, type, config) {
    if (!canvas) {
      console.error('[ChartJS] No canvas element found')
      return
    }

    // Default configuration
    const defaultConfig = {
      type: type,
      data: config.datasets ? config : {
        labels: config.labels || [],
        datasets: []
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        ...(config.options || {})
      }
    }

    try {
      this.chart = new Chart(canvas.getContext('2d'), defaultConfig)
      console.log(`[ChartJS] Created ${type} chart`)
    } catch (e) {
      console.error('[ChartJS] Failed to create chart:', e)
    }
  },

  /**
   * Destroy the current chart instance
   * @private
   */
  _destroyChart() {
    if (this.chart) {
      this.chart.destroy()
      this.chart = null
    }
  },

  /**
   * Update chart based on payload from server
   * @private
   */
  _updateChart(payload) {
    if (!this.chart) {
      console.warn('[ChartJS] Cannot update - chart not initialized')
      return
    }

    // Handle type change - requires recreation
    if (payload.type && payload.type !== this.chart.config.type) {
      const canvas = this.el.querySelector('canvas')
      this._destroyChart()
      this.chartType = payload.type
      this._createChart(canvas, payload.type, payload.data || {})
      return
    }

    // Handle full data replacement
    if (payload.data) {
      if (payload.data.labels) {
        this.chart.data.labels = payload.data.labels
      }
      if (payload.data.datasets) {
        this.chart.data.datasets = payload.data.datasets
      }
      this.chart.update()
      return
    }

    // Handle specific dataset update
    if (payload.dataset_index !== undefined && payload.dataset_data) {
      const index = payload.dataset_index
      if (this.chart.data.datasets[index]) {
        this.chart.data.datasets[index].data = payload.dataset_data
        this.chart.update()
      } else {
        console.warn(`[ChartJS] Dataset index ${index} not found`)
      }
      return
    }

    // Handle adding a new data point
    if (payload.add_data !== undefined) {
      if (payload.label) {
        this.chart.data.labels.push(payload.label)
      }
      this.chart.data.datasets.forEach((dataset, index) => {
        const value = Array.isArray(payload.add_data)
          ? payload.add_data[index]
          : payload.add_data
        dataset.data.push(value)
      })
      this.chart.update()
      return
    }

    // Handle removing the oldest data point
    if (payload.shift_data) {
      if (this.chart.data.labels.length > 0) {
        this.chart.data.labels.shift()
      }
      this.chart.data.datasets.forEach(dataset => {
        if (dataset.data.length > 0) {
          dataset.data.shift()
        }
      })
      this.chart.update()
      return
    }

    // Handle options update
    if (payload.options) {
      this.chart.options = {
        ...this.chart.options,
        ...payload.options
      }
      this.chart.update()
      return
    }

    // Default: just update the chart
    this.chart.update()
  },

  /**
   * Update chart data from config attribute
   * @private
   */
  _updateChartData(config) {
    if (!this.chart) return

    if (config.labels) {
      this.chart.data.labels = config.labels
    }

    if (config.datasets) {
      this.chart.data.datasets = config.datasets
    }

    if (config.options) {
      this.chart.options = {
        ...this.chart.options,
        ...config.options
      }
    }

    this.chart.update()
  }
}
