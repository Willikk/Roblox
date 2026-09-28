# ⚔️ Roblox AI Skills for Antigravity & Luau

High-performance, production-ready AI skills designed for building fast-paced action RPGs (such as *Deepwoken*, *Jujutsu Shenanigans*, and *Type Soul*) on Roblox with Luau.

These skills teach AI coding assistants (like Google Antigravity / Gemini) to avoid default low-quality particles and rigid animations, enforcing modern studio standards: **3D Mesh VFX**, **UV Texture Panning**, **Procedural R6 Movement**, and **Terrain Adaptation**.

---

## 📦 Included Skills

### 1. [`roblox-mesh-vfx`](./skills/roblox-mesh-vfx/)
High-end visual effects pipeline using custom 3D meshes (Blender ➔ Roblox) instead of primitive particles.
* **100% Client-Side Rendering**: Server only transmits network metadata via `UnreliableRemoteEvent`.
* **Mesh Animation & Math**: Non-uniform scaling (*Squash & Stretch*) with `TweenService` and `ExponentialOut` easing.
* **Terrain Normal Raycast Alignment**: Aligns ground shockwaves, craters, and dust to the exact slope of the terrain.
* **UV Scrolling / Texture Panning**: Real-time offsets on `RenderStepped` for energy blades, magical auras, and fluid motion.
* **Hitstop & Impact Weight**: Frame freezing on attacker and victim (0.05s - 0.10s) + Bloom/ColorCorrection micro-flashes.

### 2. [`roblox-r6-procedural-animation`](./skills/roblox-r6-procedural-animation/)
Dynamic terrain adaptation and procedural movement tailored specifically for **R6 character rigs**.
* **Dual-Leg Raycasting**: Continuous ground detection under left and right hips.
* **Pelvis Drop (Anti-Stretching)**: Automatically lowers `RootJoint.C0` when stepping on stairs or rocks so legs never float or distort.
* **Ground Normal Foot Tilting**: Rotates `Left Hip.C0` and `Right Hip.C0` to match slopes.
* **Procedural Body Leaning**: Tilts the torso forward/backward based on velocity and banking into sharp turns.
* **Head & Neck Tracking**: Smooth `Neck.C0` orientation following the camera with safe angle clamping.

---

## 🚀 How to Install & Use

### Option A: As Workspace Skills (Project-Specific)
Clone this repository into your project root. The skills are located in `.agents/skills/` and will be automatically recognized by Antigravity:
```bash
git clone https://github.com/Willikk/Roblox.git
```

### Option B: As Global Skills (Available in All Projects)
Copy the skills folders to your machine's global configuration directory:

**Windows (PowerShell):**
```powershell
Copy-Item -Path ".\skills\*" -Destination "$HOME\.gemini\config\skills\" -Recurse -Force
```

**macOS / Linux:**
```bash
cp -r ./skills/* ~/.gemini/config/skills/
```

---

## 🛠️ Tech Stack & Requirements
* **Language**: Luau (with `--!strict` typing)
* **Target Engine**: Roblox Studio
* **Rig Type**: R6 (Procedural Animation) & R6/R15 (Mesh VFX)
* **Compatible Tools**: [Rojo](https://rojo.space/), [StyLua](https://github.com/JohnnyMorganz/StyLua), [Selene](https://github.com/Kampfkarren/selene)

---

## 📄 License
MIT License. Free to use and modify for personal and commercial Roblox games.
