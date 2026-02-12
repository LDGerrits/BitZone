---
sidebar_position: 1
---

# Introduction

## Overview
**QuickZone** is a high-performance, low-footprint spatial query library for Roblox. It allows you to efficiently track when parts, models, or players enter defined zones.

Under the hood, it uses a **Bounding Volume Hierarchy (BVH)** and a **Frame Budget Scheduler** to ensure your game stays at 60 FPS, even with hundreds of zones and thousands of tracked entities.

## Installation

For wally, the package name + version is

```
ldgerrits/quickzone@^0.2.2
```

## Manual
Download the latest .rbxm model file from the [Releases](https://github.com/LDGerrits/QuickZone/releases) tab and drag it into ReplicatedStorage.

## Quick Start
Here is a complete example of setting up a 'Water Zone' that enables swimming logic for the LocalPlayer.
```lua
local Players = game:GetService('Players')
local ReplicatedStorage = game:GetService('ReplicatedStorage')
local QuickZone = require(ReplicatedStorage.QuickZone)

-- 1. Create a Group
-- LocalPlayerGroup automatically tracks the client's character (including respawns)
local myPlayer = QuickZone.LocalPlayerGroup()

-- 2. Create an Observer
-- The Observer holds the behavior. We subscribe it to our player group.
local swimObserver = QuickZone.Observer()
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

-- 3. Create a Zone
-- Create a static zone from a Part in workspace
local poolZone = QuickZone.fromPart(workspace.PoolWater)

-- 4. Connect them
-- Attach the logic (Observer) to the location (Zone)
poolZone:attach(swimObserver)
```