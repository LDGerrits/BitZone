---
sidebar_position: 1
---

# Introduction

## Overview
QuickZone is a high-performance, spatial partitioning library for Roblox. 

QuickZone makes it possible to track thousands of entities across hundreds of zones with almost no impact on your frame rate. It bypasses Roblox's physics engine in favor of geometric math while providing a predictable, budgeted, and flexible solution for zone detection.

:::info Point-Based Detection
QuickZone uses point-based detection. It checks if a specific point (e.g., the center of a Part, the position of an Attachment, or the Pivot of a Model) is inside a zone's boundary.

Because it calculates if it is inside or not using geometric math instead of physics-based volume intersections, it is significantly faster than other zone detection libraries.
:::

## Core Features

- **Fast Spatial Queries**: Process thousands of spatial queries per second with negligible FPS impact.

- **Track Anything**: Track BaseParts, Models, Attachments, Bones, Cameras, or even pure Lua tables. If it has a position, QuickZone can track it.

- **Shape Support**: Supports mathematical containment for Blocks, Balls, Cylinders, and Wedges without relying on physics collision meshes.

- **Decoupled Logic**: Decouple game logic from spatial instances. Bind behaviors to categories of entities (Players, NPCs, Projectiles) for a clean, scalable architecture.

- **Budgeted Scheduler**: Remove lag spikes by setting a hard frame budget (e.g., 1ms). Workload is smeared across frames to ensure a flat, predictable performance profile.

- **Zero-Allocation Runtime**: Engineered with Data-Oriented Design to minimize GC pressure. By using contiguous arrays and object pooling, QuickZone avoids memory-related stutters.


## Benchmarks

In a scenario with 2,000 moving entities and 100 zones recorded over 30-seconds, the obtained benchmarks were as follows:

| Metric | QuickZone | ZonePlus | SimpleZone | QuickBounds | Empty Script |
| --- | --- | --- | --- | --- | --- |
| FPS | 42.37 | 37.23 | 29.88 | 41.31 | 42.73 |
| Events/s | 2271 | 2482 | 2518 | 566 | 0 |
| Memory Usage (MB) | 2.13 | 159 | 1.77 | 2.60 | 1.04 |

## Installation

### Wally
The package name + version is

```
ldgerrits/quickzone@^0.2.2
```

### Manual
Download the latest .rbxm model file from the [Releases](https://github.com/LDGerrits/QuickZone/releases) tab and drag it into ReplicatedStorage.

## Quick Start
Here is a complete example of setting up a 'Water Zone' that enables swimming logic for the LocalPlayer.
```lua
local Players = game:GetService('Players')
local ReplicatedStorage = game:GetService('ReplicatedStorage')
local QuickZone = require(ReplicatedStorage.QuickZone)

-- Create a LocalPlayerGroup that automatically tracks the client's character (including respawns)
local myPlayer = QuickZone.LocalPlayerGroup()

-- Create an Observer that holds the behavior with a priority of 42.
-- If this player is inside multiple zones, the higher priority observer will 'win'.
local swimObserver = QuickZone.Observer(42)
swimObserver:subscribe(myPlayer)

-- Connect the events (Note: Events return cleanup functions)
swimObserver:onLocalPlayerEntered(function(zone)
    print('LocalPlayer entered water!')
    local char = Players.LocalPlayer.Character
    if char then
        char.Humanoid:SetStateEnabled(Enum.HumanoidStateType.Swimming, true)
        char.Humanoid:ChangeState(Enum.HumanoidStateType.Swimming)
    end
end)

swimObserver:onLocalPlayerExited(function(zone)
    print('LocalPlayer left water.')
    local char = Players.LocalPlayer.Character
    if char then
        char.Humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
    end
end)

-- Create a static zone from a Part in workspace
local poolZone = QuickZone.ZoneFromPart(workspace.PoolWater)

-- Attach the logic (Observer) to the location (Zone)
poolZone:attach(swimObserver)
```