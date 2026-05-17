---
sidebar_position: 1
---

# Introduction

## Why use QuickZone?

**The Physics Bottleneck.** Traditional zone libraries act as wrappers for Roblox's physics engine (e.g., `GetPartsInPart` or `.Touched`), binding spatial logic to collision meshes. This results in expensive geometry calculations, unpredictable overhead, low flexibility, and much worse performance as the number of zones grows. 

**Clean Architecture.** By separating *what* you track (Groups), *where* you track them (Zones), and *how* you respond (Observers), QuickZone eliminates monolithic, instance-bound logic and keeps your codebase clean. 

**Physics-Free Scaling.** QuickZone achieves *O(N log Z)* scaling by bypassing the physics engine in favor of pure geometric math and a custom Linear Bounding Volume Hierarchy (LBVH). Performance is driven by the number of entities, while the number of zones is virtually irrelevant.

**Agnostic.** Whether you prefer classic event-driven programming, robust lifecycle management, or zero-allocation iterators for ECS architectures, QuickZone can fit your workflow.

**Total Performance Control.** The runtime cost is entirely in your control. Through a budgeted scheduler, the workload is smeared across frames and only consumes as much CPU time as you explicitly allow. Paired with contiguous arrays that produce virtually zero garbage collection (GC) pressure, QuickZone produces a flat, predictable performance profile.

**Unit Tested.** A rigorous unit testing suite ensures stable and predictable behavior across all systems.

:::info Point-Based Detection
QuickZone uses point-based detection. It checks if a specific point (e.g., the center of a Part, the position of an Attachment, or the Pivot of a Model) is inside a zone's boundary.
:::

---

## Core Features

- **Endless Scale**: The number of zones has zero impact on performance. Maintain 60 FPS even with over a million zones in your game.

- **Track Anything**: Track Players, BaseParts, Models, Attachments, Bones, Cameras, or even custom tables. If it has a position, QuickZone can track it.

- **Budgeted Scheduler**: Set a hard frame budget (e.g., 1ms) to completely eliminate lag spikes. Workloads are smeared across frames to maintain a flat, predictable performance profile.

- **Shape Support**: Built-in for Blocks, Balls, Cylinders, Wedges and CornerWedges without relying on physics collision meshes.

- **Declarative Lifecycles**: Replace event-based logic with the observe pattern for declarative logic. There is no need to manually track `onEnter` and `onExit` states.

- **Decoupled Architecture**: Separate where tracking happens (Zones) from who is being tracked (Groups) and how the system responds (Observers). Bind complex behaviors to groups of entities with zero boilerplate.

- **ECS-Ready**: Built-in support for zero-allocation iterators and deterministic manual stepping, making it a perfect fit for ECS architectures and data-oriented workflows.

- **Zero-Allocation Runtime**: By utilizing contiguous arrays and object pooling, QuickZone produces virtually zero GC pressure to avoid memory-related stutters.

- **Dynamic Zones**: Use moving zones at very little cost. QuickZone maintains separate Static and Dynamic LBVHs for maximum efficiency.

---

## Performance Benchmarks

QuickZone was benchmarked against the most popular alternatives in two distinct scenarios: **Map Stress** (lots of zones) and **Entity Stress** (lots of moving parts).

_Note: For the QuickZone benchmark, we used a frame budget of 1ms, the entities' update rate was set to 60Hz, and precision was 0.0._

### Test 1: High Zone Count
*Scenario: 500 moving entities, 10,000 zones, recorded over 30 seconds.*

This test highlights the fundamental flaw in traditional Zone-Centric libraries. As map complexity grows, their performance degrades exponentially.

| Metric | QuickZone | ZonePlus | SimpleZone | QuickBounds | Empty Script |
| --- | --- | --- | --- | --- | --- |
| FPS | 59.25 | 3.84 | 5.53 | 58.95 | 59.28 |
| Events/s | 643 | 627 | 519 | 328 | 0 |
| Memory Usage (MB) | 18.57 | 4230 | 99.79 | 17.62 | 0.65 |

**The Result:** QuickZone maintained a perfect 60 FPS.
* ZonePlus and SimpleZone imploded, dropping to 3-5 FPS, making the game unplayable.
* ZonePlus consumed over 4 GB of memory, which would crash most mobile devices instantly.
* QuickZone proved its *O(N log Z)* algorithmic advantage.
* QuickZone vs. QuickBounds: Both libraries scaled well by maintaining ~60 FPS. However, QuickZone still maintained a slight FPS lead and, more importantly, delivered double the event throughput (643 vs 328) compared to QuickBounds.

### Test 2: High Entity Count
*Scenario: 2,000 moving entities, 100 zones, recorded over 30 seconds.*

| Metric | QuickZone | ZonePlus | SimpleZone | QuickBounds | Empty Script |
| --- | --- | --- | --- | --- | --- |
| FPS | 42.37 | 29.88 | 37.23 | 41.31 | 42.73 |
| Events/s | 2271 | 2482 | 2518 | 566 | 0 |
| Memory Usage (MB) | 2.13 | 159 | 1.77 | 2.60 | 1.04 |

**The Result:** QuickZone is the only library that maintained near-baseline FPS (-1% impact).
* ZonePlus caused a 28% drop in framerate.
* QuickZone handled the load with 98% less memory than ZonePlus.
* QuickZone vs. QuickBounds: QuickZone averages ~1 FPS higher than QuickBounds. More importantly, QuickZone processed 4x the volume of events (2,271 vs 566).

## Installation

### Wally
Add the following to your wally.toml file:

```toml
ldgerrits/quickzone@1.4.6
```

### NPM
For roblox-ts projects, install the package as follows:

```Bash
npm i @rbxts/quickzone
```

### Manual
Download the latest .rbxm model file from the [Releases](https://github.com/LDGerrits/QuickZone/releases) tab and drag it into ReplicatedStorage.

## Quick Start
The following example showcases an anti-gravity system. QuickZone supports three coding styles, so choose the one that fits your architecture.

### Option A: The Lifecycle Approach (Recommended)
Best for clean, modern code. You define relationships in a configuration table (**Declarative**) and use a single function to manage the active state (**Lifecycle**).

```lua
local QuickZone = require(game.ReplicatedStorage.QuickZone)
local Zone, Group, Observer = QuickZone.Zone, QuickZone.Group, QuickZone.Observer

-- Create a group that automatically tracks the client's character (including respawns)
local myPlayer = Group.localPlayer()

-- Find all current and future instances with the 'AntiGravity' tag.
local zones = Zone.fromTag('AntiGravity', {
    metadata = { GravityMultiplier = 0.4 }
})

-- Create an observer subscribed to the group and attached to the zones.
local gravityObserver = Observer.new({ 
    groups = { myPlayer },
    zones = { zones }
})

-- Define behavior
gravityObserver:observe(function(player, zone)
    local character = player.Character
    local hrp = character and character:FindFirstChild('HumanoidRootPart')
    if not hrp then return end
    
    -- Get the zone's gravity multiplier using metadata.
    local meta = zone:getMetadata()
    local multiplier = meta and meta.GravityMultiplier or 1
    
    -- Create the Anti-Gravity force on enter
    local force = Instance.new('BodyForce')
    force.Name = 'AntiGravityForce'
    force.Force = Vector3.new(0, hrp.AssemblyMass * workspace.Gravity * (1 - multiplier), 0)
    force.Parent = hrp

    -- Automatically destroy the force when the player exits the zone
    return function() 
        force:Destroy()
    end
end)
```

### Option B: The Event-Driven Approach (ZonePlus / SimpleZone Style)
Best for familiarity or for migrating ZonePlus code to QuickZone. You manually 'wire' objects together (**Imperative**) and use standard events like `onEnter` to trigger one-off actions (**Event-Driven**).

```lua
local QuickZone = require(game.ReplicatedStorage.QuickZone)
local Zone, Group, Observer = QuickZone.Zone, QuickZone.Group, QuickZone.Observer
local localPlayer = game:GetService('Players').LocalPlayer

local myPlayer = Group.localPlayer()
local zones = Zone.fromChildren(workspace.AntiGravityParts)
local gravityObserver = Observer.new():subscribe(myPlayer):attach(zones)

-- Connect events
gravityObserver:onLocalPlayerEnter(function(zone)
    local character = localPlayer.Character
    local hrp = character and character:FindFirstChild('HumanoidRootPart')
    if not hrp then return end

    local ref = zone:getReference() -- This returns the zone's part
    local multiplier = ref and ref:GetAttribute('GravityMultiplier') or 1 -- You can use attributes!

    local force = Instance.new('BodyForce')
    force.Name = 'AntiGravityForce'
    force.Force = Vector3.new(0, hrp.AssemblyMass * workspace.Gravity * (1 - multiplier), 0)
    force.Parent = hrp
end)

gravityObserver:onLocalPlayerExit(function(zone)
    local character = localPlayer.Character
    local hrp = character and character:FindFirstChild('HumanoidRootPart')

    if hrp and hrp:FindFirstChild('AntiGravityForce') then
        hrp.AntiGravityForce:Destroy()
    end
end)
```

### Option C: The Polling Approach (Data-Oriented / ECS)
Use iterators to poll state for continuous logic. To enhance ECS workflows, you can also turn off auto-updating and update QuickZone manually. It is even possible to manually link entities to a reference like an Id or an object.

```lua
local Players = game:GetService('Players')
local RunService = game:GetService('RunService')
local QuickZone = require(game.ReplicatedStorage.QuickZone)
local Zone, Group, Observer = QuickZone.Zone, QuickZone.Group, QuickZone.Observer

-- Disable auto-update for deterministic, manual stepping (optional)
QuickZone:setEnabled(false)

local localPlayer = Players.LocalPlayer
local characterModel = localPlayer.Character or localPlayer.CharacterAdded:Wait()

-- Track this Model's physical position, but return the local player in queries
QuickZone:setReference(characterModel, localPlayer)

-- Add the local player to the spatial group (QuickZone tracks the mapped model automatically)
local playerGroup = Group.new():add(localPlayer)
local zones = Zone.fromTag('AntiGravity', {
    metadata = { GravityMultiplier = 0.4 }
})
local gravityObserver = Observer.new({ 
    groups = { playerGroup },
    zones = { zones }
})

-- Process all spatial movement and LBVH tree updates in a specific order (only needed if :setEnabled(false))
local function spatialSystem(dt)
    QuickZone:update(dt) 
end

local function gravitySystem(dt)
    -- Instead of creating a BodyForce, we apply continuous math statelessly.
    for player, zone in gravityObserver:iterEntitiesInside() do
        local character = player.Character
        local hrp = character and character:FindFirstChild('HumanoidRootPart')
        if not hrp then continue end

        local meta = zone:getMetadata()
        local multiplier = meta and meta.GravityMultiplier or 1
        
        local upwardForce = hrp.AssemblyMass * workspace.Gravity * (1 - multiplier)
        hrp:ApplyImpulse(Vector3.new(0, upwardForce * dt, 0))
    end
end

RunService.Heartbeat:Connect(function(dt)
    spatialSystem(dt)
    gravitySystem(dt)
end)
```