// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/bezgelor_portal"
import topbar from "../vendor/topbar"
import {CharacterViewer} from "./character_viewer"
import {ChartJS} from "./hooks/chart_hook"

// ============================================
// LIVEVEW HOOKS
// ============================================

/**
 * CharacterViewer Hook
 *
 * Renders a 3D character model using Three.js.
 * Data attributes:
 *   - data-race: Character race key (e.g., "human", "aurin")
 *   - data-gender: Character gender ("male" or "female")
 *   - data-equipment: JSON array of equipped item IDs
 */
const CharacterViewerHook = {
  mounted() {
    this.destroyed = false
    const race = this.el.dataset.race || "human"
    const gender = this.el.dataset.gender || "male"

    // Parse equipment data if provided
    let equipment = []
    try {
      equipment = JSON.parse(this.el.dataset.equipment || "[]")
    } catch (e) {
      console.warn("Failed to parse equipment data:", e)
    }

    // Defer heavy WebGL initialization to prevent blocking navigation
    // Use requestIdleCallback for browsers that support it, otherwise setTimeout
    const deferInit = window.requestIdleCallback || ((cb) => setTimeout(cb, 1))

    deferInit(() => {
      // Check if we were destroyed during the defer
      if (this.destroyed) {
        console.log("[CharacterViewer] Destroyed before init")
        return
      }

      console.log("[CharacterViewer] Creating viewer for", race, gender)

      // Create the viewer (this creates WebGL context)
      this.viewer = new CharacterViewer(this.el, {
        width: this.el.clientWidth || 400,
        height: this.el.clientHeight || 500,
      })

      console.log("[CharacterViewer] Viewer created, container size:", this.el.clientWidth, "x", this.el.clientHeight)

      // Check if WebGL initialization failed
      if (this.viewer.initFailed) {
        console.warn("[CharacterViewer] WebGL initialization failed, showing fallback")
        this._showFallback("WebGL not available")
        this.viewer = null
        return
      }

      // Check again after viewer creation
      if (this.destroyed) {
        this.viewer?.dispose()
        this.viewer = null
        return
      }

      // Load the character model
      const modelUrl = `/models/characters/${race}_${gender}.glb`
      console.log("[CharacterViewer] Loading model:", modelUrl)
      this.currentModelUrl = modelUrl
      this.currentRace = race
      this.currentGender = gender
      this.viewer.loadModel(modelUrl).then((success) => {
        console.log("[CharacterViewer] Model load result:", success)
        if (this.destroyed) return
        if (success) {
          // Hide the loading spinner
          this._hideSpinner()
          // Show animation controls if animations available
          this._showAnimationControls()
          // Load texture for this race/gender
          this.viewer.loadTexture(race, gender)
        } else {
          // Show fallback message if model fails to load
          console.log("[CharacterViewer] Showing fallback")
          this._showFallback()
        }
      }).catch(err => {
        console.error("[CharacterViewer] Model load error:", err)
        this._showFallback()
      })

      // Handle resize
      this.resizeObserver = new ResizeObserver((entries) => {
        for (const entry of entries) {
          const { width, height } = entry.contentRect
          if (this.viewer && width > 0 && height > 0) {
            this.viewer.resize(width, height)
          }
        }
      })
      this.resizeObserver.observe(this.el)
    })
  },

  updated() {
    // Reload model if race/gender changed
    const race = this.el.dataset.race || "human"
    const gender = this.el.dataset.gender || "male"
    const modelUrl = `/models/characters/${race}_${gender}.glb`

    if (this.viewer && this.currentModelUrl !== modelUrl) {
      this.currentModelUrl = modelUrl
      this.currentRace = race
      this.currentGender = gender
      this.viewer.loadModel(modelUrl).then((success) => {
        if (success) {
          this._hideSpinner()
          this.viewer.loadTexture(race, gender)
        } else {
          this._showFallback()
        }
      })
    }
  },

  destroyed() {
    // Set flag first to stop any pending async operations
    this.destroyed = true

    if (this.resizeObserver) {
      this.resizeObserver.disconnect()
      this.resizeObserver = null
    }

    if (this.viewer) {
      this.viewer.dispose()
      this.viewer = null
    }
  },

  _hideSpinner() {
    // Remove the loading spinner element
    const spinner = this.el.querySelector('.loading')
    if (spinner && spinner.parentElement) {
      spinner.parentElement.remove()
    }
  },

  _showAnimationControls() {
    const animations = this.viewer.getAnimations()

    // Only show controls if there are animations
    if (animations.length === 0) {
      return
    }

    // Remove existing controls
    const existing = this.el.querySelector('.animation-controls')
    if (existing) existing.remove()

    // Create animation control panel
    const controls = document.createElement('div')
    controls.className = 'animation-controls absolute bottom-2 left-2 right-2 flex gap-1 flex-wrap justify-center'

    animations.forEach(({ index, name }) => {
      const btn = document.createElement('button')
      btn.className = 'btn btn-xs btn-ghost bg-base-100/80'
      btn.textContent = name
      btn.addEventListener('click', () => {
        this.viewer.playAnimation(index)
        // Update active state
        controls.querySelectorAll('button').forEach(b => b.classList.remove('btn-active'))
        btn.classList.add('btn-active')
      })
      // Mark first as active
      if (index === 0) btn.classList.add('btn-active')
      controls.appendChild(btn)
    })

    this.el.appendChild(controls)
  },

  _showFallback(reason) {
    // Clear the container and show a fallback message
    const isWebGLIssue = reason === "WebGL not available"
    const message = isWebGLIssue
      ? "3D preview requires WebGL"
      : "Character preview not available"
    const hint = isWebGLIssue
      ? "Try enabling hardware acceleration in your browser settings"
      : ""

    this.el.innerHTML = `
      <div class="flex items-center justify-center h-full text-base-content/50">
        <div class="text-center py-12">
          <svg xmlns="http://www.w3.org/2000/svg" class="h-12 w-12 mx-auto mb-2 opacity-50" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5.121 17.804A13.937 13.937 0 0112 16c2.5 0 4.847.655 6.879 1.804M15 10a3 3 0 11-6 0 3 3 0 016 0zm6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
          </svg>
          <p>${message}</p>
          ${hint ? `<p class="text-xs mt-1 opacity-70">${hint}</p>` : ""}
        </div>
      </div>
      <!-- Work in Progress Banner -->
      <div class="absolute inset-0 pointer-events-none overflow-hidden">
        <div
          class="absolute text-black text-xs font-bold text-center py-1 shadow-lg"
          style="background-color: #f7941d; width: 200px; top: 38px; left: -52px; transform: rotate(-45deg);"
        >
          Work in Progress
        </div>
      </div>
    `
  },
}

// Combine hooks
const Hooks = {
  ...colocatedHooks,
  CharacterViewer: CharacterViewerHook,
  ChartJS: ChartJS,
}

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: Hooks,
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// Handle file downloads from LiveView
window.addEventListener("phx:download", (event) => {
  const {filename, content, content_type} = event.detail
  const blob = new Blob([content], {type: content_type})
  const url = URL.createObjectURL(blob)
  const a = document.createElement("a")
  a.href = url
  a.download = filename
  document.body.appendChild(a)
  a.click()
  document.body.removeChild(a)
  URL.revokeObjectURL(url)
})

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// ============================================
// GAMING WEBSITE ANIMATIONS
// ============================================

// Scroll-triggered animations using Intersection Observer
const initScrollAnimations = () => {
  const animatedElements = document.querySelectorAll('.animate-on-scroll, .stagger-children')

  if (animatedElements.length === 0) return

  const observer = new IntersectionObserver((entries) => {
    entries.forEach(entry => {
      if (entry.isIntersecting) {
        entry.target.classList.add('visible')
        // Optionally unobserve after animation
        // observer.unobserve(entry.target)
      }
    })
  }, {
    threshold: 0.1,
    rootMargin: '0px 0px -50px 0px'
  })

  animatedElements.forEach(el => observer.observe(el))
}

// Navbar scroll behavior - adds 'scrolled' class when scrolled
const initNavbarScroll = () => {
  const navbar = document.querySelector('.navbar-gaming')
  if (!navbar) return

  const handleScroll = () => {
    if (window.scrollY > 50) {
      navbar.classList.add('scrolled')
    } else {
      navbar.classList.remove('scrolled')
    }
  }

  window.addEventListener('scroll', handleScroll, { passive: true })
  handleScroll() // Check initial state
}

// Parallax effect for floating elements
const initParallax = () => {
  const floatElements = document.querySelectorAll('.hero-float')
  if (floatElements.length === 0) return

  window.addEventListener('mousemove', (e) => {
    const x = (e.clientX / window.innerWidth - 0.5) * 2
    const y = (e.clientY / window.innerHeight - 0.5) * 2

    floatElements.forEach((el, index) => {
      const speed = (index + 1) * 10
      el.style.transform = `translate(${x * speed}px, ${y * speed}px)`
    })
  }, { passive: true })
}

// Smooth scroll for anchor links
const initSmoothScroll = () => {
  document.querySelectorAll('a[href^="#"]').forEach(anchor => {
    anchor.addEventListener('click', function(e) {
      const targetId = this.getAttribute('href')
      if (targetId === '#') return

      const target = document.querySelector(targetId)
      if (target) {
        e.preventDefault()
        target.scrollIntoView({
          behavior: 'smooth',
          block: 'start'
        })
      }
    })
  })
}

// Counter animation for stats
const initCounterAnimation = () => {
  const counters = document.querySelectorAll('[data-counter]')
  if (counters.length === 0) return

  const animateCounter = (el) => {
    const target = parseInt(el.getAttribute('data-counter'))
    const duration = 2000
    const step = target / (duration / 16)
    let current = 0

    const update = () => {
      current += step
      if (current < target) {
        el.textContent = Math.floor(current).toLocaleString()
        requestAnimationFrame(update)
      } else {
        el.textContent = target.toLocaleString()
      }
    }

    update()
  }

  const observer = new IntersectionObserver((entries) => {
    entries.forEach(entry => {
      if (entry.isIntersecting) {
        animateCounter(entry.target)
        observer.unobserve(entry.target)
      }
    })
  }, { threshold: 0.5 })

  counters.forEach(counter => observer.observe(counter))
}

// Glitch effect on hover (for glitch-hover elements)
const initGlitchEffect = () => {
  const glitchElements = document.querySelectorAll('.glitch-hover')
  glitchElements.forEach(el => {
    el.addEventListener('mouseenter', () => {
      el.classList.add('glitching')
      setTimeout(() => el.classList.remove('glitching'), 300)
    })
  })
}

// Back to top button
const initBackToTop = () => {
  const btn = document.getElementById('back-to-top')
  if (!btn) return

  window.addEventListener('scroll', () => {
    if (window.scrollY > 500) {
      btn.classList.add('visible')
    } else {
      btn.classList.remove('visible')
    }
  }, { passive: true })

  btn.addEventListener('click', () => {
    window.scrollTo({ top: 0, behavior: 'smooth' })
  })
}

// Magnetic hover effect for buttons - DISABLED for flat design
const initMagneticButtons = () => {
  // Disabled - keeping buttons flat without movement
}

// Tilt effect for cards - DISABLED for flat design
const initCardTilt = () => {
  // Disabled - keeping cards flat without 3D tilt
}

// Initialize all gaming animations on DOM ready
document.addEventListener('DOMContentLoaded', () => {
  initScrollAnimations()
  initNavbarScroll()
  initParallax()
  initSmoothScroll()
  initCounterAnimation()
  initGlitchEffect()
  initBackToTop()
  initMagneticButtons()
  initCardTilt()
})

// Re-initialize after LiveView navigation
window.addEventListener('phx:page-loading-stop', () => {
  // Small delay to ensure DOM is updated
  setTimeout(() => {
    initScrollAnimations()
    initNavbarScroll()
    initParallax()
    initSmoothScroll()
    initCounterAnimation()
    initGlitchEffect()
    initBackToTop()
    initMagneticButtons()
    initCardTilt()
  }, 100)
})

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", _e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}

