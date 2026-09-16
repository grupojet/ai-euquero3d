let THREE;

let renderer;
let scene;
let camera;
let object;
let initialized = false;
let stage;

function dims(project, proposal) {
  const p = proposal?.parameter_changes || {};
  const base = project?.parameters || {};
  return {
    width: Number(p.width_mm ?? base.width_mm ?? 100),
    depth: Number(p.depth_mm ?? base.depth_mm ?? 70),
    height: Number(p.height_mm ?? base.height_mm ?? 35),
  };
}

async function init() {
  if (!THREE) {
    THREE = await import("https://cdn.jsdelivr.net/npm/three@0.180.0/build/three.module.js");
  }
  stage = document.getElementById("previewStage");
  if (!stage) return false;
  stage.innerHTML = "";
  scene = new THREE.Scene();
  camera = new THREE.PerspectiveCamera(42, 1, 0.1, 2000);
  camera.position.set(180, 150, 180);
  renderer = new THREE.WebGLRenderer({ antialias: true, alpha: true });
  renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
  stage.appendChild(renderer.domElement);
  const hemi = new THREE.HemisphereLight(0xc9efff, 0x10263a, 2.2);
  scene.add(hemi);
  const dir = new THREE.DirectionalLight(0xffffff, 2.4);
  dir.position.set(140, 180, 120);
  scene.add(dir);
  scene.add(new THREE.GridHelper(360, 18, 0x2b5875, 0x17364c));
  window.addEventListener("resize", resize);
  initialized = true;
  resize();
  return true;
}

function resize() {
  if (!initialized || !stage) return;
  const w = Math.max(stage.clientWidth, 320);
  const h = Math.max(stage.clientHeight, 220);
  renderer.setSize(w, h, false);
  camera.aspect = w / h;
  camera.updateProjectionMatrix();
  renderer.render(scene, camera);
}

function animate() {
  if (!initialized) return;
  requestAnimationFrame(animate);
  if (object) object.rotation.y += 0.0018;
  renderer.render(scene, camera);
}

export async function updatePreview(project, proposal) {
  try {
    if (!initialized && !(await init())) return;
    if (object) {
      scene.remove(object);
      object.geometry.dispose();
      object.material.dispose();
    }
    const d = dims(project, proposal);
    const geometry = new THREE.BoxGeometry(Math.max(d.width, 1), Math.max(d.height, 1), Math.max(d.depth, 1));
    const material = new THREE.MeshStandardMaterial({ color: 0x209fd1, metalness: 0.18, roughness: 0.42, transparent: true, opacity: 0.88 });
    object = new THREE.Mesh(geometry, material);
    object.position.y = Math.max(d.height, 1) / 2;
    const edges = new THREE.LineSegments(new THREE.EdgesGeometry(geometry), new THREE.LineBasicMaterial({ color: 0x91ecff }));
    object.add(edges);
    scene.add(object);
    const largest = Math.max(d.width, d.depth, d.height, 80);
    camera.position.set(largest * 1.6, largest * 1.2, largest * 1.6);
    camera.lookAt(0, d.height / 2, 0);
    resize();
    if (!renderer.setAnimationLoop) animate(); else renderer.setAnimationLoop(() => { if (object) object.rotation.y += 0.0018; renderer.render(scene, camera); });
  } catch (error) {
    renderPreviewUnavailable(`Preview 3D indisponível: ${error.message}`);
  }
}

export function renderPreviewUnavailable(message) {
  const target = document.getElementById("previewStage");
  if (!target) return;
  target.innerHTML = `<div class="preview-placeholder"><div class="cube-icon">◇</div><b>Preview schematic indisponível</b><span></span></div>`;
  target.querySelector("span").textContent = message;
}
