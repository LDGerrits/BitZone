---
sidebar_position: 2
---

# Usage

## Zones

Zones represent physical areas in the world. They are mathematical boundaries that can be static (fixed in space) or dynamic (following a part). They can be created from existing parts or defined manually with a CFrame and Size.

### Creation
The easiest way to create a zone.

```lua
-- Static Zone (Fastest)
-- Ideal for shops, biomes, or permanent regions.
local staticZone = QuickZone.ZoneFromPart(workspace.SafeZone)

-- Dynamic Zone
-- Passing 'true' makes the zone follow the part's CFrame on :update()
local trainZone = QuickZone.ZoneFromPart(workspace.TrainCarriage, true)
```

### Manual Creation
Useful for procedural generation or areas without physical parts.

```lua
local zone = QuickZone.Zone(
    CFrame.new(0, 10, 0),       -- Position and rotation
    Vector3.new(20, 20, 20),    -- Size
    'Block',                    -- Shape: 'Block', 'Ball', 'Cylinder', or 'Wedge'
    nil,                        -- No associated part
    false                       -- Static (false) or dynamic (true)
)
```

### Updating Zones
If you create a zone manually or want to sync a dynamic zone to a new reference, use `:update()`.

```lua
-- Manually move a zone
zone:update(CFrame.new(0, 50, 0), Vector3.new(10, 10, 10))

-- Sync a dynamic zone to its associated part
dynamicZone:update()
```

## Groups

Groups are collections of entities (Parts, Models, Players, etc.) that you want to track. They allow you to categorize entities and set unique performance costs for each category.

### Specialized Groups
QuickZone provides specialized groups that automatically handle player joining, leaving, and respawning.

```lua
-- Tracks all players in the server
local allPlayers = QuickZone.PlayerGroup()

-- Tracks only the local player (client-side only)
local myPlayer = QuickZone.LocalPlayerGroup()
```

### Custom Groups
For NPCs, projectiles, or vehicles, create a standard Group.

```lua
local projectiles = QuickZone.Group({
    updateRate = 60,   -- Check every frame for high-speed objects
    precision = 0,     -- Query every time it moves
    safety = false     -- Fire callbacks immediately (faster but risky if you yield)
})

local idleNPCs = QuickZone.Group({
    updateRate = 5,    -- Check only 5 times a second
    precision = 2.0    -- Only query if the NPC moves more than 2 studs
})
```

### Adding Entities
You can add BaseParts, Models, Attachments, Bones, or even tables with a Position.

```lua
-- Add a Model (tracks the PrimaryPart or Pivot)
enemies:add(npcModel, { Team = 'Red' })

-- Add a specific Attachment (tracks the exact point)
-- This is great for offsets if you do not want to track the middle of a part (e.g. sword tip)
enemies:add(sword.TipAttachment, { Damage = 75 })

-- Add a table
local spell = { Position = Vector3.new(10, 5, 0) }
enemies:add(spell)

-- Remove when done
enemies:remove(npcModel)
```

_Note: The second argument (`metadata`) is optional and will be passed to your event callbacks._

## Observers

Observers are the 'brain' of QuickZone. They connect Groups to Zones.

### Setup
An Observer listens to its subscribed Groups and checks if they overlap with its attached Zones.

```lua
local observer = QuickZone.Observer()

observer:subscribe(allPlayers) -- Who to watch
healingZone:attach(observer)   -- Where to watch
```

### Events
Events are defined on the Observer, not the Zone or Group. Events return a cleanup function. Calling this function is equivalent to 'disconnecting' the listener.

```lua
-- Fires when an entity enters a zone for this observer
local disconnect = observer:onEntered(function(entity, zone, metadata)
    print(entity.Name .. " entered " .. zone:getId())
end)

-- Convenience Player wrappers
observer:onPlayerEntered(function(player, zone) ... end)
observer:onLocalPlayerEntered(function(zone) ... end)
observer:onPlayerExited(function(player, zone) ... end)
```

### Priority & Resolution
Observers use a priority system to handle overlapping zones. An entity 'belongs' to only one zone state per observer at a time when using priorities.

```lua
local lowPriority = QuickZone.Observer(0)
local highPriority = QuickZone.Observer(10)

-- If a player is inside Zone A (Low) and Zone B (High) simultaneously:
-- 1. highPriority:onEntered() fires for Zone B.
-- 2. lowPriority:onEntered() fires for Zone A.
```

### Handling State
You can toggle an observer's activity state. This is useful for disabling triggers during cutscenes or rounds.

```lua
observer:setEnabled(false) -- Fires 'onExited' for everyone inside
task.wait(5)
observer:setEnabled(true)  -- Fires 'onEntered' if they are still there
```

## Utility

### Frame Budget
QuickZone uses a scheduler to prevent lag. You can adjust how much time (in seconds) it is allowed to use per frame.

```lua
-- Allow 0.5 milliseconds per frame (default is 1ms)
QuickZone:setFrameBudget(0.5/1000)
```

### Spatial Queries
Perform instant checks without using the Observer/Group pattern.

```lua
-- Get all zones at a specific vector
local zones = QuickZone:getZonesAtPoint(Vector3.new(10, 5, 0))

-- Get the group an entity belongs to
local group = QuickZone:getGroupOfEntity(workspace.Part)
```

### Debugging
Enable the visualizer to see zone boundaries and whether they are used or not.

```lua
QuickZone:visualize(true)
```

## Considerations

- **Point-Based Tracking:** QuickZone tracks points (the center of a Part, the Attachment's position, etc.), not the volume of the part itself.
- **Attachments:** If you need to track a specific part of a character, add an `Attachment` to that part and track the Attachment.
- **Scheduling:** To maintain high FPS, QuickZone uses frame budget and smears workload across frames. As a consequence, an entity entering a zone might be detected a few frames later if thousands of calculations are queued.