<div align="center">
	<h1>QuickZone</h1>
	<p>A lightweight spatial library for Roblox that replaces expensive physics queries with fast, math-based entity tracking at scale.</p>
	<a href="https://LDGerrits.github.io/QuickZone/"><strong>View docs</strong></a>
</div>
<!--moonwave-hide-before-this-line-->


## Why use QuickZone?

Traditional zone libraries like ZonePlus and SimpleZone act as wrappers for Roblox's physics engine (e.g., `GetBoundsInBox`, `GetPartsInPart` or `.Touched`), resulting in expensive collision geometry calculations and synchronization overhead. QuickZone bypasses the physics engine in favor of geometric math, data-oriented design and smart processing, making it performant even in complex scenes.

## What it offers

- **Fast Spatial Queries**: Process thousands of spatial queries per second with negligible FPS impact.

- **Track Anything**: Track BaseParts, Models, Attachments, Bones, Cameras, or even pure Lua tables. If it has a position, QuickZone can track it.

- **Shape Support**: Supports mathematical containment for Blocks, Balls, Cylinders, and Wedges without relying on physics collision meshes.

- **Decoupled Architecture**: Separate game logic from spatial instances. Bind behaviors to categories of entities (Players, NPCs, Projectiles) for a clean, scalable architecture.

- **Budgeted Scheduler**: Remove lag spikes by setting a hard frame budget (e.g., 1ms). Workload is smeared across frames to maintain a flat and predictable performance profile.

- **Zero-Allocation Runtime**: By using contiguous arrays and object pooling, QuickZone reduces GC pressure, avoiding memory-related stutters.
