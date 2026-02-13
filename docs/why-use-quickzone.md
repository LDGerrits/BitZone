---
sidebar_position: 3
---

# Why use QuickZone?

Traditional zone libraries like ZonePlus and SimpleZone act as wrappers for Roblox's internal physics queries. Such libraries may use basic Bounding Volume Hierarchy (BVHs), but, ultimately, rely on the physics engine (e.g., `GetBoundsInBox`, `GetPartsInPart` or `.Touched`), resulting in expensive collision geometry calculations and synchronization overhead.

## The QuickZone Approach

QuickZone bypasses the physics engine in favor of geometric math and data-oriented design. It implements a Linear BVH that resolves spatial queries using math compiled to machine code to bypass interpreter overhead.

### 1. The Entity-Centric Model

Traditional libraries are Zone-Centric. They iterate through every Zone instance and query the physics engine for overlapping parts (i.e. entities in QuickZone-terms).

- **The Scaling Problem**: Performance worsens as you add more zones (*O(Z)*), even if the number of entities remains static.

QuickZone, on the other hand, is Entity-Centric. It keeps a list of entities and queries them against an LBVH (*O(N log Z)*). 

- **The Benefit**: This means that you can have hundreds, even thousands, of zones with very low runtime cost. The cost effectively becomes a factor of the number of entities that are being tracked.

### 2. Data-Oriented Design

QuickZone is built on Data-Oriented principles, shifting the focus from 'objects' to how data is laid out in memory.

- **Contiguous Arrays**: Unlike standard OOP where data is scattered across the heap in different objects, QuickZone stores entity data in pre-allocated, contiguous arrays. This maximizes CPU cache locality, improving processing speed.

- **Stable Memory**: By using flat arrays and object pooling, QuickZone generates almost no garbage during runtime. This prevents lag spikes caused by the GC.

### 3. Architecture

QuickZone moves away from binding logic to specific Instances. Instead, it uses a topology of Groups and Observers which separates what is being tracked from where it is being tracked and how to react to that.

#### Groups
A Group is a collection of entities that share performance characteristics and logical categorization.

Performance can be configured per Group, allowing for granular optimization like this:

- `CameraGroup`: Real-time frequency (60Hz), zero tolerance.

- `PlayerGroup`: High frequency (30Hz), high precision.

- `NPCGroup`: Low frequency (2Hz), low precision.

This prevents 'wasting' CPU cycles checking a slow-moving NPC, for example.

#### Observers
An Observer is a system that bridges Groups and Zones.

- Observers subscribe to specific Groups.

- Zones (the 'where') attach to specific Observers.

This creates a Many-to-Many relationship that allows for fast and decoupled logic.

```lua
-- Create an Observer and subscribe to a group
local safeObserver = QuickZone.Observer()
safeObserver:subscribe(QuickZone.LocalPlayerGroup())

-- Logic is defined once, not per zone
safeObserver:onEntered(function(player, zone)
    print('Entered Safe Zone:', zone:getId())
end)

-- Create Zones from parts and attach them to the observer
for _, part in workspace.SafeZones:GetChildren() do
    if part:IsA('BasePart') then
        local zone = QuickZone.ZoneFromPart(part)
        zone:attach(safeObserver)
    end
end
```

### 4. The Budgeted Scheduler
A common issue with spatial libraries is stutter due to it processing too many things in one frame. QuickZone fixes this via its smart Scheduler.

#### Frame Budgeting
You can set a hard time limit (e.g., 1ms). The Scheduler monitors os.clock() in real-time. If the budget is met, the system pauses immediately and resumes in the next frame. This guarantees that QuickZone will never be the cause of a frame drop.

#### Workload Smearing
The scheduler smears updates across frames. This means that, if you have a Group of 600 entities updating at 10Hz, QuickZone will process exactly 100 entities per frame at 60 fps. This ensures that we have flat, predictable performance profile with no peaks or valleys.

#### No starvation
The Scheduler uses a Round-Robin strategy for Group processing. Instead of processing groups in order, QuickZone cycles through them fairly. This prevents the issue where a heavy group keeps consuming the entire frame budget and 'starving' the subsequent groups.

### 5. Flexibility
Because QuickZone relies on pure math rather than the Physics engine, it is not limited to BaseParts. It also supports duck typing for entities.

- **BaseParts**: Uses `.Position`.

- **Models**: Uses `.PrimaryPart.Position` or `:GetPivot()` (if `.PrimaryPart` does not exist).

- **Attachments/Bones**: Uses `.WorldPosition`.

- **Cameras**: Uses `.CFrame.Position`.

- **Tables**: Uses any custom `.Position`, `.WorldPosition` and `.CFrame` field, or `:GetPivot()`.

This allows you to track real-time simulations (e.g. a spell cast or an RC car) without the overhead of creating physical Instances.

### 6. Performance Benchmarks

In a scenario with 2,000 moving entities and 100 zones, recorded over 30-seconds, I obtained the following benchmarks:

| Metric | QuickZone | ZonePlus | SimpleZone | QuickBounds | Empty Script |
| --- | --- | --- | --- | --- | --- |
| FPS | 42.37 | 37.23 | 29.88 | 41.31 | 42.73 |
| Events/s | 2271 | 2482 | 2518 | 566 | 0 |
| Memory Usage (MB) | 2.13 | 159 | 1.77 | 2.60 | 1.04 |

_Note: For the QuickZone benchmark, we used a frame budget of 1ms, the entities' update rate was set to 60Hz, and the precision was 0.0._

The benchmarks show that QuickZone's negative impact on FPS was quite negligible compared to the empty script baseline. In comparison, ZonePlus drops the game to ~29 FPS under the same load, introducing significant stutter, while SimpleZone drops frames by ~13%. QuickZone proves that you can run complex spatial logic without taxing the render loop.

Furthermore, QuickZone only used 2.13 MB of memory. In comparison, ZonePlus bloats to 159 MB. QuickZone's use of flat arrays and object pooling keeps the memory footprint ~98% smaller.

While QuickBounds has similar, if not slightly worse, FPS and memory usage, QuickZone handles 4x the event volume (2271 vs 566 events/s). This validates the shift to the Linear BVH, contiguous arrays, caching, and starvation prevention techniques, allowing the system to process thousands of spatial queries per second without bottlenecking the CPU.