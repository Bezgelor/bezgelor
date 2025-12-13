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

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks},
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

