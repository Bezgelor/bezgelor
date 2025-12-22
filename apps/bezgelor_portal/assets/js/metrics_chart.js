// Chart.js hook for Phoenix LiveView
// Metrics-specific chart with time-series support

const MetricsChart = {
  mounted() {
    this.chart = null
    this.initChart()

    // Listen for update events with chart-specific ID
    // Event name format: "update_chart_${chartId}"
    const chartId = this.el.id
    if (chartId) {
      this.handleEvent(`update_chart_${chartId}`, (data) => {
        this.updateChart(data)
      })
    }

    // Also listen for generic update_chart event
    this.handleEvent("update_chart", (data) => {
      this.updateChart(data)
    })
  },

  initChart() {
    // Chart is available via window.Chart from app.js import
    if (typeof Chart === "undefined") {
      console.error("Chart.js not loaded")
      return
    }

    const ctx = this.el.getContext("2d")
    const chartType = this.el.dataset.chartType || "line"
    const chartTitle = this.el.dataset.chartTitle || ""

    this.chart = new Chart(ctx, {
      type: chartType,
      data: {
        labels: [],
        datasets: []
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        plugins: {
          legend: {
            position: "top"
          },
          title: {
            display: !!chartTitle,
            text: chartTitle
          }
        },
        scales: {
          x: {
            type: "time",
            time: {
              unit: "minute",
              displayFormats: {
                minute: "HH:mm",
                hour: "HH:mm",
                day: "MMM d"
              }
            }
          },
          y: {
            beginAtZero: true
          }
        }
      }
    })
  },

  updateChart(data) {
    if (!this.chart) return

    // Update time unit based on data range
    if (data.timeUnit) {
      this.chart.options.scales.x.time.unit = data.timeUnit
    }

    this.chart.data.labels = data.labels || []
    this.chart.data.datasets = data.datasets || []
    this.chart.update("none") // No animation for live updates
  },

  destroyed() {
    if (this.chart) {
      this.chart.destroy()
    }
  }
}

export default MetricsChart
