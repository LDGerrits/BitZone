---
sidebar_position: 3
---

# Why use QuickZone?

Before integrating a new library, you might need some convincing of why you shouldn't just use Roblox's built-in `.Touched` event or `workspace:GetPartsInPart`. That's totally fair! The following text explains the engineering challenges of spatial queries in Roblox and how QuickZone solves them through advanced algorithms and low-level optimizations.

## The Problem with Physics

Traditionally, developers rely on the Roblox Physics engine to detect when a player enters a zone.

### The `.Touched` Event
The `.Touched` event is the oldest method. It relies on physical collisions.
- **Tunneling:** Fast-moving objects (like cars or falling players) can skip over a zone entirely between physics steps, never firing the event.
- **Performance:** It requires parts to be physically present in the workspace. If you have 1,000 zones, you have 1,000 extra parts adding to the physics simulation overhead, even if they are `CanCollide = false`.
- **Reliability:** It doesn't fire if the part is not moving relative to the zone.

### Spatial Queries (`GetPartsInPart`)
The modern alternative is `workspace:GetPartsInPart`. While accurate, it is effectively a 'Brute Force' physics check.
- **Cost:** It has to calculate precise collision geometry (OOB/Convex Decomposition). Doing this for 50 zones every frame is incredibly expensive.
- **Garbage:** It allocates a new table and new instances every time you call it, causing frequent Garbage Collection (GC) spikes.

## The QuickZone Solution

QuickZone was built with one goal: **Maximum Performance with Minimal Footprint.** It bypasses the physics engine entirely in favor of pure geometric math and data-oriented design.

### 1. Bounding Volume Hierarchy (BVH)

If you have 100 players and 100 zones, a naive script would perform 10,000 checks per frame ($O(N \times M)$). As your game grows, this logic causes lag.

QuickZone implements a **Linear Bounding Volume Hierarchy**.
A BVH organizes your zones into a tree structure. When checking if a player is in a zone, we first check the 'root' of the tree. If the player isn't in the root, we instantly know they aren't in *any* of the 1,000 zones inside it.

This turns an $O(N)$ search into an $O(\log N)$ search. In practice, this means QuickZone can query thousands of zones in microseconds.

### 2. Data-Oriented Design (DOD)

Most Lua libraries heavily use Object-Oriented Programming (OOP), creating a new table/class for every single bullet or entity.
- **The Problem:** Lua tables are expensive memory allocations. Creating wrapper objects (`Entity.new(part)`) for 1,000 projectiles creates massive GC pressure (lag spikes).
- **The Solution:** QuickZone uses a Data-Oriented approach. We don't wrap your parts in objects. We track them in flat arrays and use the Instances themselves as keys.

This results in **Zero-Allocation Hot Loops**. Once the system is running, the scheduler generates almost no garbage, keeping your memory usage flat and your GC pauses non-existent.

### 3. The Frame Budget (Fixing Starvation)

A common issue with loop-based checks is 'Starvation.'
If you have 5,000 zombies to check, the loop might take 8ms. If your game is already running heavy logic, that 8ms push might drop you below 60 FPS.

QuickZone includes a **Frame Budget Scheduler**.
1. You set a budget (e.g., 2ms).
2. The scheduler processes as many entities as it can within that 2ms.
3. If it runs out of time, it **pauses** and resumes exactly where it left off on the next frame.

This guarantees that **QuickZone will never be the cause of your frame drops**, no matter how many entities you throw at it. It favors 'Eventual Consistency' over 'Lag.'

## Implementation Detail

Let's look at a comparison.

**The Naive Way (Laggy):**
```lua
RunService.Heartbeat:Connect(function()
    for _, zone in zones do
        -- Allocates a new table every single frame for every single zone
        local parts = workspace:GetPartsInPart(zone.Part) 
        for _, part in parts do
            -- heavy logic...
        end
    end
end)