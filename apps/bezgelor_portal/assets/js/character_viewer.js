/**
 * 3D Character Viewer using Three.js
 *
 * Renders WildStar character models in glTF format with orbit controls
 * and animation playback support.
 */
import * as THREE from "three";
import { OrbitControls } from "three/addons/controls/OrbitControls.js";
import { GLTFLoader } from "three/addons/loaders/GLTFLoader.js";

export class CharacterViewer {
  /**
   * Create a new CharacterViewer instance.
   *
   * @param {HTMLElement} container - DOM element to render into
   * @param {Object} options - Configuration options
   * @param {number} options.width - Viewport width (default: container width or 400)
   * @param {number} options.height - Viewport height (default: 500)
   * @param {number} options.backgroundColor - Background color (default: 0x1a1a2e)
   */
  constructor(container, options = {}) {
    this.container = container;
    this.options = {
      width: options.width || container.clientWidth || 400,
      height: options.height || 500,
      backgroundColor: options.backgroundColor || 0x1a1a2e,
      ...options,
    };

    this.scene = null;
    this.camera = null;
    this.renderer = null;
    this.controls = null;
    this.model = null;
    this.mixer = null;
    this.clock = new THREE.Clock();
    this.animationId = null;

    this._init();
  }

  /**
   * Initialize the Three.js scene, camera, renderer, and controls.
   */
  _init() {
    // Scene
    this.scene = new THREE.Scene();
    this.scene.background = new THREE.Color(this.options.backgroundColor);

    // Camera
    this.camera = new THREE.PerspectiveCamera(
      45,
      this.options.width / this.options.height,
      0.1,
      1000
    );
    this.camera.position.set(0, 1.5, 3);

    // Renderer
    this.renderer = new THREE.WebGLRenderer({ antialias: true });
    this.renderer.setSize(this.options.width, this.options.height);
    this.renderer.setPixelRatio(window.devicePixelRatio);
    this.renderer.outputColorSpace = THREE.SRGBColorSpace;
    this.container.appendChild(this.renderer.domElement);

    // Controls
    this.controls = new OrbitControls(this.camera, this.renderer.domElement);
    this.controls.target.set(0, 1, 0);
    this.controls.enableDamping = true;
    this.controls.dampingFactor = 0.05;
    this.controls.update();

    // Lighting
    const ambientLight = new THREE.AmbientLight(0xffffff, 0.6);
    this.scene.add(ambientLight);

    const directionalLight = new THREE.DirectionalLight(0xffffff, 0.8);
    directionalLight.position.set(5, 10, 7.5);
    directionalLight.castShadow = true;
    this.scene.add(directionalLight);

    // Add a subtle fill light from below
    const fillLight = new THREE.DirectionalLight(0xffffff, 0.3);
    fillLight.position.set(-5, -5, -5);
    this.scene.add(fillLight);

    // Start render loop
    this._animate();
  }

  /**
   * Load a glTF/GLB model from URL.
   *
   * @param {string} url - URL to the glTF/GLB file
   * @returns {Promise<boolean>} - True if load succeeded
   */
  async loadModel(url) {
    const loader = new GLTFLoader();

    try {
      const gltf = await loader.loadAsync(url);

      // Remove old model
      if (this.model) {
        this.scene.remove(this.model);
        if (this.mixer) {
          this.mixer.stopAllAction();
          this.mixer = null;
        }
      }

      this.model = gltf.scene;

      // Center and scale the model
      const box = new THREE.Box3().setFromObject(this.model);
      const center = box.getCenter(new THREE.Vector3());
      const size = box.getSize(new THREE.Vector3());

      // Center the model
      this.model.position.x = -center.x;
      this.model.position.y = -box.min.y;
      this.model.position.z = -center.z;

      // Scale to fit in view (target height around 2 units)
      const maxDim = Math.max(size.x, size.y, size.z);
      if (maxDim > 2) {
        const scale = 2 / maxDim;
        this.model.scale.setScalar(scale);
      }

      this.scene.add(this.model);

      // Setup animations if present
      if (gltf.animations && gltf.animations.length > 0) {
        this.mixer = new THREE.AnimationMixer(this.model);

        // Play the first animation (usually idle)
        const idleAnimation = gltf.animations[0];
        const action = this.mixer.clipAction(idleAnimation);
        action.play();
      }

      // Update camera target to model center
      this.controls.target.set(0, size.y / 2, 0);
      this.controls.update();

      return true;
    } catch (error) {
      console.error("Failed to load model:", error);
      return false;
    }
  }

  /**
   * Play a specific animation by name or index.
   *
   * @param {string|number} animation - Animation name or index
   */
  playAnimation(animation) {
    if (!this.mixer || !this.model) return;

    // Stop current animations
    this.mixer.stopAllAction();

    // Find and play the requested animation
    const clips = this.model.animations || [];
    let clip = null;

    if (typeof animation === "number" && clips[animation]) {
      clip = clips[animation];
    } else if (typeof animation === "string") {
      clip = clips.find((c) => c.name === animation);
    }

    if (clip) {
      const action = this.mixer.clipAction(clip);
      action.play();
    }
  }

  /**
   * Animation loop.
   */
  _animate() {
    this.animationId = requestAnimationFrame(() => this._animate());

    const delta = this.clock.getDelta();

    if (this.mixer) {
      this.mixer.update(delta);
    }

    this.controls.update();
    this.renderer.render(this.scene, this.camera);
  }

  /**
   * Resize the viewport.
   *
   * @param {number} width - New width
   * @param {number} height - New height
   */
  resize(width, height) {
    this.options.width = width;
    this.options.height = height;

    this.camera.aspect = width / height;
    this.camera.updateProjectionMatrix();

    this.renderer.setSize(width, height);
  }

  /**
   * Clean up and dispose resources.
   */
  dispose() {
    if (this.animationId) {
      cancelAnimationFrame(this.animationId);
      this.animationId = null;
    }

    if (this.mixer) {
      this.mixer.stopAllAction();
      this.mixer = null;
    }

    if (this.model) {
      this.scene.remove(this.model);
      this._disposeObject(this.model);
      this.model = null;
    }

    if (this.controls) {
      this.controls.dispose();
      this.controls = null;
    }

    if (this.renderer) {
      this.renderer.dispose();
      if (this.renderer.domElement.parentNode) {
        this.renderer.domElement.parentNode.removeChild(
          this.renderer.domElement
        );
      }
      this.renderer = null;
    }

    this.scene = null;
    this.camera = null;
  }

  /**
   * Recursively dispose of an object and its children.
   */
  _disposeObject(obj) {
    if (obj.geometry) {
      obj.geometry.dispose();
    }

    if (obj.material) {
      if (Array.isArray(obj.material)) {
        obj.material.forEach((m) => m.dispose());
      } else {
        obj.material.dispose();
      }
    }

    if (obj.children) {
      obj.children.forEach((child) => this._disposeObject(child));
    }
  }
}

export default CharacterViewer;
