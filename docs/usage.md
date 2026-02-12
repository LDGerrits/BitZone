---
sidebar_position: 2
---

# Usage

## Zones ('Where')

Zones represent physical areas in your world. They can be created from existing parts or defined manually with a CFrame and Size.

### From a Part
The easiest way to create a zone.

```lua
-- Static Zone (e.g. a pool of water)
local zone = QuickZone.fromPart(workspace.Pool)

-- Dynamic Zone (e.g. a moving train carriage)
-- Pass 'true' as the second argument
local trainZone = QuickZone.fromPart(workspace.TrainCar, true)
```

### Manual Creation
Useful for procedural generation or abstract areas.

```lua
local zone = QuickZone.Zone(
    CFrame.new(0, 10, 0),       -- Position/Rotation
    Vector3.new(20, 20, 20),    -- Size
    'Block',                    -- Shape: 'Block', 'Ball', 'Cylinder', or 'Wedge'
    nil,                        -- No associated part
    false                       -- Static (false) or Dynamic (true)
)
```

### Lifecycle
When you are done with a zone, destroy it to clean up memory.

```lua
zone:destroy()
```

## Groups ('Who')

Groups are collections of entities (Parts, Models, Players, etc.) that you want to track.

### Player Groups
QuickZone provides specialized groups that automatically handle player joining, leaving, and respawning.

```lua
-- Tracks ALL players in the server
local allPlayers = QuickZone.PlayerGroup()

-- Tracks ONLY the local player (Client-side only)
local myPlayer = QuickZone.LocalPlayerGroup()
```

### Custom Groups
For NPCs, projectiles, or vehicles, create a standard Group.

```lua
-- Create a group with custom config
local enemies = QuickZone.Group({
    updateRate = 10,  -- Check 10 times per second (defaults to 30)
    safety = true     -- Use task.spawn for callbacks (safer but slightly slower)
})
```

### Adding Entities
You can add BaseParts, Models, Attachments, Bones, or even raw tables with a Position.

```lua
-- Add a Model (Tracks the PrimaryPart or Pivot)
enemies:add(npcModel, { Team = 'Red' })

-- Add a specific Attachment (Tracks the exact point)
-- This is great for precise hitboxes (e.g. sword tip)
enemies:add(character.HeadAttachment, { IsHeadshot = true })

-- Remove when done
enemies:remove(npcModel)
```

_Note: The second argument (`customData`) is optional and will be passed to your event callbacks._

## Observers ('Logic')

Observers are the 'brain' of QuickZone. They connect **Groups** to **Zones**.

### Setup
1. **Create** an Observer.
2. **Subscribe** to a Group (tell it _who_ to watch).
3. **Attach** to a Zone (tell it _where_ to watch).

```lua
local observer = QuickZone.Observer()

-- Watch the 'enemies' group
observer:subscribe(enemies)

-- Listen for events in the 'lava' zone
lavaZone:attach(observer)
```

### Events
Events are defined on the **Observer**, not the Zone or Group.

```lua
-- Generic Entity Event
observer:onEntered(function(entity, zone, customData)
    print(entity.Name, 'entered zone', zone:getId())
    if customData then
        print('Team:', customData.Team)
    end
end)

-- Convenience wrapper for Players
observer:onPlayerEntered(function(player, zone)
    print(player.Name, 'stepped in!')
end)

-- Clean up events
local connection = observer:onExited(function(entity, zone)
    print('Entity left')
end)

connection() -- Disconnects this specific listener
```

### Priority & State
You can disable an observer temporarily (e.g., during a cutscene). This will force an `onExited` event for all currently tracked entities, ensuring logic stops cleanly.

```lua
observer:setEnabled(false) -- Fires 'onExited' for everyone inside
task.wait(5)
observer:setEnabled(true)  -- Fires 'onEntered' if they are still there
```

## Utility

### Frame Budget
QuickZone uses a scheduler to prevent lag. You can adjust how much time (in seconds) it is allowed to use per frame.

```lua
-- Allow 2 milliseconds per frame (default is 1ms)
QuickZone:setFrameBudget(0.002)
```

### Visualizer
Debug your zones by seeing exactly what the library sees.

```lua
QuickZone:visualize(true)
```

### Spatial Queries
You can check 'What is here?' without setting up an observer.

```lua
-- Get all zones at a specific vector
local zones = QuickZone:getZonesAtPoint(Vector3.new(10, 5, 0))

-- Get the group an entity belongs to
local group = QuickZone:getGroupOfEntity(workspace.Part)
```

## Considerations

- **Point-Based Tracking:** QuickZone tracks **points** (the center of a Part, the Attachment's position, etc.), not the volume of the part itself per default.
- **Attachments:** For precise hitboxes (e.g., a sword tip entering a shield zone), use `Attachment` instances.
- **Eventual Consistency:** Because of the frame budget, an entity entering a zone might be detected a few frames later if thousands of calculations are queued. This ensures minimal negative impact on FPS but means detection is not strictly instantaneous.