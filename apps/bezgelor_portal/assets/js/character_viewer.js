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

      console.log("Model bounds:", { min: box.min, max: box.max, center, size });

      // Calculate scale to fit in view (target height around 2 units)
      const maxDim = Math.max(size.x, size.y, size.z);
      const scale = maxDim > 0 ? 2 / maxDim : 1;

      console.log("Applying scale:", scale);

      // Center the model (scale the offsets since scale is applied first in the matrix)
      this.model.position.x = -center.x * scale;
      this.model.position.y = -box.min.y * scale;
      this.model.position.z = -center.z * scale;
      this.model.scale.setScalar(scale);

      this.scene.add(this.model);

      // Setup animations if present
      this.animations = gltf.animations || [];
      this.currentAnimation = null;

      if (this.animations.length > 0) {
        this.mixer = new THREE.AnimationMixer(this.model);
        // Play the first animation by default
        this.playAnimation(0);
      }

      console.log("Available animations:", this.animations.map((a, i) => `${i}: ${a.name || "unnamed"}`));

      // Update camera target to scaled model center (model is now ~2 units tall)
      const scaledHeight = size.y * scale;
      this.controls.target.set(0, scaledHeight / 2, 0);
      this.controls.update();

      return true;
    } catch (error) {
      console.error("Failed to load model:", error);
      return false;
    }
  }

  /**
   * Get list of available animations.
   *
   * @returns {Array<{index: number, name: string}>} Animation list
   */
  getAnimations() {
    return (this.animations || []).map((clip, index) => ({
      index,
      name: clip.name || `Animation ${index + 1}`,
    }));
  }

  /**
   * Play a specific animation by name or index.
   *
   * @param {string|number} animation - Animation name or index
   */
  playAnimation(animation) {
    if (!this.mixer) return;

    // Stop current animations
    this.mixer.stopAllAction();

    // Find and play the requested animation
    const clips = this.animations || [];
    let clip = null;

    if (typeof animation === "number" && clips[animation]) {
      clip = clips[animation];
      this.currentAnimation = animation;
    } else if (typeof animation === "string") {
      clip = clips.find((c) => c.name === animation);
      this.currentAnimation = clips.indexOf(clip);
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

  /**
   * Load and apply skin texture for character.
   *
   * @param {string} race - Race name (e.g., "human", "draken")
   * @param {string} gender - Gender ("male" or "female")
   */
  async loadTexture(race, gender) {
    if (!this.model) return;

    // Map race/gender to texture path patterns
    const textureMap = {
      'human_male': '/textures/characters/Human/Male/CHR_Human_M_Skin_LightBlack_01_Color.Skin_Body.png',
      'human_female': '/textures/characters/Human/Female/CHR_Human_F_Face_B_01_Color.Skin_Body.png',
      'cassian_male': '/textures/characters/Human/Male/CHR_Human_M_Skin_LightBlack_01_Color.Skin_Body.png',
      'cassian_female': '/textures/characters/Human/Female/CHR_Human_F_Face_B_01_Color.Skin_Body.png',
      'draken_male': '/textures/characters/Draken/Male/CHR_DrakenMale_Skin_01_Color.Skin_Body.png',
      'draken_female': '/textures/characters/Draken/Female/CHR_Draken_F_Color.Skin_Body.png',
      'granok_male': '/textures/characters/Granok/Male/CHR_Granok_M_Skin_01_Color.Skin_Body.png',
      'granok_female': '/textures/characters/Granok/Female/CHR_Granok_F_Skin_01_Color.Skin_Body.png',
      'mechari_female': '/textures/characters/Mechari/Female/CHR_Mechari_F_Skin_01_Color.Skin_Body.png',
      'chua_male': '/textures/characters/Chua/Male/CHR_Chua_M_Skin_A_01_Color.Skin_Body.png',
    };

    const key = `${race}_${gender}`;
    const texturePath = textureMap[key];

    if (!texturePath) {
      console.log(`No texture mapping for ${key}`);
      return;
    }

    const textureLoader = new THREE.TextureLoader();

    try {
      const texture = await textureLoader.loadAsync(texturePath);
      texture.colorSpace = THREE.SRGBColorSpace;
      texture.flipY = false;

      // Apply texture to all meshes
      this.model.traverse((child) => {
        if (child.isMesh && child.material) {
          child.material.map = texture;
          child.material.needsUpdate = true;
        }
      });

      console.log(`Loaded texture: ${texturePath}`);
    } catch (error) {
      console.log(`Texture not found: ${texturePath}`);
    }
  }
}

export default CharacterViewer;
