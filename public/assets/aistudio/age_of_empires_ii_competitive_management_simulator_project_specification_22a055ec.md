# Age of Empires II Competitive Management Simulator
## Comprehensive Project Specification & Architectural Blueprint

### 1. Vision & Executive Summary
The **Age of Empires II Competitive Management Simulator** is a standalone, desktop-first simulation game where players step into the shoes of an esports team manager and coach in the competitive *Age of Empires II: Definitive Edition* scene. 

Unlike traditional real-time strategy games where players control units on the battlefield, this simulator focuses entirely on the macro-level aspects of competitive gaming: roster management, scouting player talent, contract negotiations, training schedules, morale systems, financial health, map drafting (using Captains Mode logic), and tactical preparation against AI or human opponents.

The application is engineered using a high-performance **Tauri + React + Rust** stack. This architecture ensures a lightning-fast native desktop footprint with zero server dependency, complete offline capability, and a robust simulation engine written in Rust to handle complex multi-season loops and tick-based match simulations seamlessly.

---

### 2. Core Architecture & Tech Stack

```
[ User Interface (React / TypeScript) ]
                   │
                   ▼ (Tauri IPC Bridge)
[ Simulation Core & Game Logic (Rust) ]
                   │
                   ▼
[ Embedded SQLite Database (Static Assets / ETL Pipeline) ]
```

* **Frontend (Presentation & UI):** Built with **React** and **TypeScript**, styled via **Tailwind CSS**. It provides a snappy, modern dashboard for managing players, checking league standings, setting training schedules, and running draft lobbies.
* **Backend Bridge:** **Tauri** acts as the secure inter-process communication (IPC) layer, linking the web-based UI directly to the native operating system and the simulation core without needing an embedded Node.js server.
* **Simulation Engine (Rust):** A high-performance Rust core responsible for game state updates, matchmaking formulas, fatigue/stress decay, economy management, and play-by-play simulation loops inspired by modern sports management engines (`fbsim-core`).
* **Data Storage:** A pre-compiled **SQLite** database containing normalized metadata, unit stats, civilization tech trees, and historical ELO distributions.

---

### 3. Data Pipeline & ETL (Ingestion Strategy)

To ensure the simulator runs smoothly offline without relying on external web requests during gameplay, an automated ETL pipeline is executed during the build process:

1. **Extraction (Extract):** 
   * Pulls structural metadata and tech trees from the open-source community repository `SiegeEngineers/aoe2techtree` (`data.json`).
   * Fetches aggregated match metadata and historical win-rate matrices from community resources like `aoestats.io`.
2. **Transformation (Transform):** 
   * Normalizes real-world player ELO ratings into internal attribute scales ($1-100$).
   * Parses win-rate percentages into dynamic matchup modifier matrices used by the match simulation engine.
3. **Chargement (Load):** 
   * Compiles all processed data into a single, static SQLite database (`aoe2_manager.db`) embedded directly within the application's binary distribution.

---

### 4. Key Gameplay Systems

#### A. Roster & Talent Management
* **Attributes:** Players possess discrete attributes reflecting real AoE2 skills: *Macro Speed*, *Micro Control*, *Wall/Defense Awareness*, *Adaptability*, *Mental Resilience (Tilt factor)*, and *Stamina/Fatigue*.
* **Contracts & Finances:** Manage weekly wage budgets, sign free agents, negotiate buyout clauses, and keep sponsors happy by meeting regional tournament objectives.
* **Staff Hiring:** Employ specialized coaches, analysts, and sports psychologists to boost team synergy and accelerate training progress.

#### B. The Drafting Phase (Captains Mode Integration)
* Matches begin with a tactical pick-and-ban phase inspired by *AoE Captains Mode* (`aoe2cm.net`).
* Managers must analyze opponent map pools and civilization win rates to ban unfavorable maps (e.g., Arabia, Arena, Nomad) and strategically draft civilizations to counter the opposing team's strengths.

#### C. Match Simulation Engine
* **Macro & Micro Simulation:** Rather than rendering 3D graphics, the Rust engine simulates matches through discrete time slices (ticks). It calculates resource collection rates, age-up timings (Dark Age $\rightarrow$ Feudal $\rightarrow$ Castle $\rightarrow$ Imperial), military production queues, and engagement outcomes based on unit counters and player micro ratings.
* **Live Match Viewer:** An immersive text and graphical dashboard displaying live score curves, resource graphs, current military counts, and dynamic commentary logs.

---

### 5. Development Roadmap

* **Phase 1: Core Engine in Rust**
  * Develop the standalone CLI simulation harness in Rust.
  * Validate mathematical balance between macro-economy, military composition, fatigue decay, and match outcome probability models.
* **Phase 2: Tauri Integration & Database Layer**
  * Set up the Tauri boilerplate linking React to Rust commands via IPC.
  * Implement the SQLite data layer containing civilizations, units, technologies, and base player pools.
* **Phase 3: Frontend Dashboard & Draft UI**
  * Build the React management screens (Dashboard, Roster, Finances, Scouting, Training).
  * Implement the interactive Captains Mode draft interface.
* **Phase 4: Packaging & Distribution**
  * Configure multi-platform build scripts via PyInstaller/Tauri bundler for Windows and macOS.
  * Conduct stress tests and quality assurance on clean operating system installations.

---

### 6. References & Community Acknowledgments
* **Siege Engineers Collective:** [`github.com/SiegeEngineers`](https://github.com/SiegeEngineers) — Providers of open-source AoE2 tooling, tech trees, and data standards.
* **Captains Mode API:** [`aoe2cm.net`](https://aoe2cm.net/) — Reference implementation for competitive drafting rules.
* **Architecture Inspiration:** Open-source sports simulation frameworks including `fbsim-core` and community-driven sports management models.