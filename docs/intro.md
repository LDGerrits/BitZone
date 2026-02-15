---
sidebar_position: 1
---

# Introduction

## Overview
QuickZone is a lightweight spatial library for Roblox that replaces expensive physics queries with fast, math-based entity tracking at scale. Instead of the physics engine, it uses geometric math while providing a predictable, budgeted, and flexible solution for zone detection, making it possible to track thousands of entities across hundreds of zones with very little impact on your frame rate.

:::info Point-Based Detection
QuickZone uses point-based detection. It checks if a specific point (e.g., the center of a Part, the position of an Attachment, or the Pivot of a Model) is inside a zone's boundary.

Because it calculates if it is inside or not using geometric math instead of physics-based volume intersections, it is significantly faster than other zone detection libraries.
:::

## Core Features

- **Lifecycle Management**: Use the `observe` pattern for 100% reliable cleanup. There is no need for juggling `onEntered` and `onExited` events anymore (do note that QuickZone still supports Event-Driven Programming).

- **Track Anything**: Track BaseParts, Models, Attachments, Bones, Cameras, or even pure Lua tables. If it has a position, QuickZone can track it.

- **Shape Support**: Supports mathematical containment for Blocks, Balls, Cylinders, and Wedges without relying on physics collision meshes.

- **Decoupled Architecture**: Separate game logic from spatial instances. Bind behaviors to categories of entities (Players, NPCs, Projectiles) for a clean, scalable architecture.

- **Budgeted Scheduler**: Remove lag spikes by setting a hard frame budget (e.g., 1ms). Workload is smeared across frames to maintain a flat and predictable performance profile.

- **Zero-Allocation Runtime**: By using contiguous arrays and object pooling, QuickZone reduces GC pressure, avoiding memory-related stutters.


## Benchmarks

The following benchmarks were recorded over 30 seconds with 2,000 moving entities and 100 zones.

| Metric | QuickZone | ZonePlus | SimpleZone | QuickBounds | Empty Script |
| --- | --- | --- | --- | --- | --- |
| FPS | 42.37 | 29.88 | 37.23 | 41.31 | 42.73 |
| Events/s | 2271 | 2482 | 2518 | 566 | 0 |
| Memory Usage (MB) | 2.13 | 159 | 1.77 | 2.60 | 1.04 |

## Installation

### Wally
The package name + version is

```
ldgerrits/quickzone@^0.3.0
```

### Manual
Download the latest .rbxm model file from the [Releases](https://github.com/LDGerrits/QuickZone/releases) tab and drag it into ReplicatedStorage.

## Quick Start
The following example demonstrates a 'Water Zone' system. It uses an Observer to apply swimming logic to the LocalPlayerGroup only when they are inside a specific area.
```lua
local Players = game:GetService('Players')
local ReplicatedStorage = game:GetService('ReplicatedStorage')
local QuickZone = require(ReplicatedStorage.QuickZone)

-- Create a LocalPlayerGroup that automatically tracks the client's character (including respawns)
local myPlayer = QuickZone.LocalPlayerGroup()

-- Create an observer with a priority of 42. If zones overlap, higher priority observers resolve first.
local swimObserver = QuickZone.Observer(42)
swimObserver:subscribe(myPlayer)

-- Define behavior
swimObserver:observeLocalPlayer(function()
    local chararcter = Players.LocalPlayer.Character
    if not character then return end

    local humanoid = character:FindFirstChild("Humanoid")
    if not humanoid then return end
    
    humanoid:SetStateEnabled(Enum.HumanoidStateType.Swimming, true)
    humanoid:ChangeState(Enum.HumanoidStateType.Swimming)

    return function() 
        humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
    end)
end)

-- Create zones and attach them to the observer to let the observer 'see'
local poolZone = QuickZone.ZoneFromPart(workspace.PoolWater)
poolZone:attach(swimObserver)
```