--!strict

local Players = game:GetService('Players')
local RunService = game:GetService('RunService')

local Group = require(script.Classes.Group)
local Geometry = require(script.Core.Geometry)
local LinearBVH = require(script.Core.LinearBVH)
local Types = require(script.Types)
local State = require(script.State)
local Zone = require(script.Classes.Zone)
local Observer = require(script.Classes.Observer)
local Config = require(script.Config)
local Scheduler = require(script.Core.Scheduler)

local staticShapes = State.staticShapes
local dynamicShapes = State.dynamicShapes
local zoneAttachedObservers = State.zoneAttachedObservers
local observerIdToObserverObj = State.observerIdToObserverObj

local foundIdsCache = {}

local sharedPlayerGroup: Types.Group?
local sharedLocalPlayerGroup: Types.Group?
local bridgeRefreshPlayerGroup: ((Player) -> ())?

local debugConnection: RBXScriptConnection?
local debugFolder: Folder?
local debugVisuals = {} :: { [number]: BoxHandleAdornment }

local IS_CLIENT = RunService:IsClient()

export type QuickZone = Types.QuickZone
export type Zone = Types.Zone
export type Observer = Types.Observer
export type Group = Types.Group
export type Entity = Types.Entity

local function trackPlayer(group: Types.Group, player: Player, trackerStore: { [Player]: () -> () })
	if trackerStore[player] then
		return
	end

	local charConns: { RBXScriptConnection } = {}
	local currentHrp: BasePart? = nil

	local function cleanCharacter()
		if currentHrp then
			group:remove(currentHrp)
			currentHrp = nil
		end
		for _, c in charConns do
			c:Disconnect()
		end
		table.clear(charConns)
	end

	local function onCharAdded(char: Model)
		cleanCharacter()

		task.spawn(function()
			-- To prioritize LocalPlayerGroup, do early return if it is local player and LocalPlayerGroup exists
			if
				IS_CLIENT
				and group == sharedPlayerGroup
				and player == Players.LocalPlayer
				and sharedLocalPlayerGroup
			then
				return
			end

			local hrp = char:WaitForChild('HumanoidRootPart', 10)

			if not hrp or not player:IsDescendantOf(Players) then
				return
			end

			if player.Character ~= char then
				return
			end

			if hrp:IsA('BasePart') then
				currentHrp = hrp

				group:add(hrp, { Player = player }) -- Custom data is needed to trigger specific player events

				table.insert(
					charConns,
					hrp.AncestryChanged:Connect(function(_, parent)
						if not parent then
							cleanCharacter()
						end
					end)
				)
			end
		end)
	end

	local addedConn = player.CharacterAdded:Connect(onCharAdded)

	trackerStore[player] = function()
		addedConn:Disconnect()
		cleanCharacter()
	end

	if player.Character then
		onCharAdded(player.Character)
	end
end

local function untrackPlayer(player: Player, trackerStore: { [Player]: () -> () })
	local cleanup = trackerStore[player]
	if cleanup then
		cleanup()
		trackerStore[player] = nil
	end
end

--[=[
	QuickZone is a high-performance spatial partitioning library for Roblox. 

	@class QuickZone
]=]
local QuickZone = {}

--[=[ 
	Creates a Zone object.

	```lua
	local zone = QuickZone.Zone({
		cframe = CFrame.new(0, 10, 0),
		size = Vector3.new(10, 10, 10),
		shape = 'Block',
		metadata = { Name = "Lobby" }
	})
	```

	:::caution Performance
	If this zone moves (e.g., attached to a moving platform) or changes size, 
	you **must** set `isDynamic` to `true`. 

	Static zones are optimized into a large, pre-calculated tree. Updating a 
	static zone forces a full recalculation of that tree, which is expensive. 
	Dynamic zones are handled separately and are much cheaper to update.
	:::

	@tag Constructor
	@param config ZoneConfig
	@return Zone
]=]
function QuickZone.Zone(config: {
	cframe: CFrame,
	size: Vector3,
	shape: Types.ShapeType,
	part: BasePart?,
	isDynamic: boolean?,
	metadata: any?,
}): Zone
	return Zone.new(config.cframe, config.size, config.shape, config.part, config.isDynamic, config.metadata)
end

--[=[ 
	Creates a Zone automatically based on a Part's properties.
	Supported shapes: Block, Ball (Spheres), Cylinder, and Wedge.

	@tag Constructor
	@param part BasePart -- The part to derive the zone from.
	@param isDynamic boolean? -- Whether the zone should follow the part every frame.
	@return Zone
]=]
function QuickZone.ZoneFromPart(part: BasePart, isDynamic: boolean?, metadata: any?): Zone
	local shape: Types.ShapeType = 'Block'
	if (part :: any).Shape == Enum.PartType.Ball then
		shape = 'Ball'
	elseif (part :: any).Shape == Enum.PartType.Cylinder then
		shape = 'Cylinder'
	elseif part:IsA('WedgePart') then
		shape = 'Wedge'
	end
	return Zone.new(part.CFrame, part.Size, shape, part, isDynamic, metadata)
end

--[=[ 
	Creates an Observer. Observers listen for entities entering or exiting assigned Zones.

	:::info Resolution Priority
	The `priority` value is used to resolve overlaps. When an entity is 
	inside multiple zones watched by different observers, higher priority 
	observers take precedence in specific logic chains.
	:::

	@tag Constructor
	@param priority number? -- The priority level (defaults to 0).
	@return Observer
]=]
function QuickZone.Observer(priority: number?): Observer
	return Observer.new(priority)
end

--[=[ 
	Creates a generic Group. 
	Groups manage collections of Entities (any instance with a position in the world like BaseParts, Models, Attachments, etc.) that Observers should track.

	```lua
	local myGroup = QuickZone.Group({
		updateRate = 20, -- Check at 20Hz
		precision = 0.5, -- Ignore movement smaller than 0.5 studs
		safety = true    -- Wrap callbacks in task.spawn
	})
	```

	@tag Constructor
	@param config { updateRate: number?, precision: number?, safety: boolean? }?
	@return Group
]=]
function QuickZone.Group(config: {
	updateRate: number?,
	precision: number?,
	safety: boolean?,
}?): Group
	return Group.new(config)
end

--[=[ 
	Returns a singleton Group that automatically tracks all Players in the server.

	:::info Behavior
	* Automatically tracks the `HumanoidRootPart` of every player.
	* Handles `PlayerAdded` and `CharacterAdded` internally.
	* If a LocalPlayerGroup exists on the client, the local player is excluded 
	  from this group to avoid duplicate tracking.
	:::

	@tag Constructor
	@param config { updateRate: number?, precision: number?, safety: boolean? }?
	@return Group
]=]
function QuickZone.PlayerGroup(config: {
	updateRate: number?,
	precision: number?,
	safety: boolean?,
}?): Group
	if sharedPlayerGroup then
		if config then
			sharedPlayerGroup:setConfig(config)
		end
		return sharedPlayerGroup
	end

	local group = Group.new(config)
	sharedPlayerGroup = group

	local trackerStore = {} :: { [Player]: () -> () }
	local mainConnections = {} :: { RBXScriptConnection }

	bridgeRefreshPlayerGroup = function(player: Player)
		untrackPlayer(player, trackerStore)
		trackPlayer(group, player, trackerStore)
	end

	table.insert(
		mainConnections,
		Players.PlayerAdded:Connect(function(player)
			trackPlayer(group, player, trackerStore)
		end)
	)

	table.insert(
		mainConnections,
		Players.PlayerRemoving:Connect(function(player)
			untrackPlayer(player, trackerStore)
		end)
	)

	for _, player in Players:GetPlayers() do
		trackPlayer(group, player, trackerStore)
	end

	local originalDestroyHook = group.destroy
	group.destroy = function(self)
		for _, conn in mainConnections do
			conn:Disconnect()
		end
		for _, cleanup in trackerStore do
			cleanup()
		end

		table.clear(mainConnections)
		table.clear(trackerStore)

		bridgeRefreshPlayerGroup = nil
		sharedPlayerGroup = nil

		originalDestroyHook(self)
	end

	return group
end

--[=[ 
	Returns a singleton Group that tracks only the LocalPlayer.

	:::info Behavior
	* This group takes 'ownership of the local player's character.
	* When this group is destroyed, the local player is automatically handed back 
	  to the global `PlayerGroup` if it exists.
	:::

	@client
	@tag Constructor
	@param config { updateRate: number?, precision: number?, safety: boolean? }?
	@return Group
]=]
function QuickZone.LocalPlayerGroup(config: {
	updateRate: number?,
	precision: number?,
	safety: boolean?,
}?): Group
	assert(IS_CLIENT, '[QuickZone] QuickZone.LocalPlayerGroup can only be called on the Client.')

	if sharedLocalPlayerGroup then
		if config then
			sharedLocalPlayerGroup:setConfig(config)
		end
		return sharedLocalPlayerGroup
	end

	local group = Group.new(config)
	sharedLocalPlayerGroup = group

	local lp = Players.LocalPlayer
	local trackers = {}

	trackPlayer(group, lp, trackers)

	local originalDestroyHook = group.destroy
	group.destroy = function(self)
		untrackPlayer(lp, trackers)
		sharedLocalPlayerGroup = nil

		-- The player should immediately be handed over to PlayerGroup
		if bridgeRefreshPlayerGroup then
			bridgeRefreshPlayerGroup(Players.LocalPlayer)
		end

		originalDestroyHook(self)
	end

	return group
end

--[=[ 
	Sets the global execution budget for the Scheduler per frame in milliseconds.
	
	The Scheduler will 'dispatch' entity updates until this threshold is reached, 
	at which point it yields until the next frame to prevent render stutter.
	
	Defaults to 1ms.

	```lua
	-- Allow QuickZone to use up to 0.5ms of frame time
	QuickZone:setFrameBudget(0.5)
	```

	@method setFrameBudget
	@within QuickZone
	@param ms number -- Time in milliseconds
	@return QuickZone
]=]
function QuickZone:setFrameBudget(ms: number): QuickZone
	local s = ms / 1000
	Scheduler.setFrameBudget(s)
	return QuickZone
end

--[=[ 
	Performs a spatial query to find all Zones containing the given point.

	@method getZonesAtPoint
	@within QuickZone
	@param position Vector3 -- The world position to check.
	@return { Zone }
]=]
function QuickZone:getZonesAtPoint(position: Vector3): { Zone }
	local results = {}

	local function checkZone(zoneId: number, shapeList: { [number]: Types.BoundingVolume })
		if Geometry.isPointInShape(position, shapeList[zoneId]) then
			local zone = State.zoneIdToZoneObj[zoneId]
			if zone then
				table.insert(results, zone)
			end
		end
	end

	if State.dynamicRootNode then
		LinearBVH.queryPoint(State.dynamicRootNode, position, function(zoneId)
			checkZone(zoneId, dynamicShapes)
		end)
	end

	if State.staticRootNode then
		LinearBVH.queryPoint(State.staticRootNode, position, function(zoneId)
			checkZone(zoneId, staticShapes)
		end)
	end

	return results
end

--[=[ 
	Finds all Observers whose assigned Zones contain the given point.

	@method getObserversAtPoint
	@within QuickZone
	@param position Vector3 -- The world position to check.
	@return { Observer }
]=]
function QuickZone:getObserversAtPoint(position: Vector3): { Observer }
	table.clear(foundIdsCache)
	local results = {}

	local function checkZone(zoneId: number, shapeList: { [number]: Types.BoundingVolume })
		if not Geometry.isPointInShape(position, shapeList[zoneId]) then
			return
		end

		local observers = zoneAttachedObservers[zoneId]
		if not observers then
			return
		end

		for _, id in observers do
			if foundIdsCache[id] then
				continue
			end
			foundIdsCache[id] = true

			local observer = observerIdToObserverObj[id]
			if observer then
				table.insert(results, observer)
			end
		end
	end

	if State.dynamicRootNode then
		LinearBVH.queryPoint(State.dynamicRootNode, position, function(zoneId)
			checkZone(zoneId, dynamicShapes)
		end)
	end

	if State.staticRootNode then
		LinearBVH.queryPoint(State.staticRootNode, position, function(zoneId)
			checkZone(zoneId, staticShapes)
		end)
	end

	return results
end

--[=[ 
	Returns the Group that the specified entity currently belongs to.

	@method getGroupOfEntity
	@within QuickZone
	@param entity Entity -- The Part, Model, or Table entity.
	@return Group?
]=]
function QuickZone:getGroupOfEntity(entity: Types.Entity): Types.Group?
	local groupId = State.entityToGroup[entity]
	if groupId then
		return State.groups[groupId]
	end
	return nil
end

--[=[ 
	Returns an array containing every Zone currently registered in the system.
	This includes both static and dynamic zones.

	@method getZones
	@within QuickZone
	@return { Zone }
]=]
function QuickZone:getZones(): { Types.Zone }
	local result = {}
	for _, zone in State.zoneIdToZoneObj do
		table.insert(result, zone)
	end
	return result
end

--[=[ 
	Returns an array of all Observers currently existing in the system.

	@method getObservers
	@within QuickZone
	@return { Observer }
]=]
function QuickZone:getObservers(): { Types.Observer }
	local result = {}
	for _, observer in State.observerIdToObserverObj do
		table.insert(result, observer)
	end
	return result
end

--[=[ 
	Returns an array of all Groups (including PlayerGroups) currently 
	registered in the system.

	@method getGroups
	@within QuickZone
	@return { Group }
]=]
function QuickZone:getGroups(): { Types.Group }
	local result = {}
	for _, group in State.groups do
		table.insert(result, group)
	end
	return result
end

--[=[ 
	Returns a flattened array of every Entity (Parts, Models, etc.) currently 
	being tracked across all Groups.

	@method getEntities
	@within QuickZone
	@return { Entity }
]=]
function QuickZone:getEntities(): { Types.Entity }
	local result = {}
	for _, group in State.groups do
		local count = #group.entities
		if count > 0 then
			local currentSize = #result
			table.move(group.entities, 1, count, currentSize + 1, result)
		end
	end
	return result
end

--[=[ 
	Enables or disables visual rendering of all registered Zones.
	Static and Dynamic zones are colored differently based on their active status.

	@tag Debug
	@method visualize
	@within QuickZone
	@param enabled boolean -- Whether to show the debug visuals.
	@return QuickZone
]=]
function QuickZone:visualize(enabled: boolean): QuickZone
	if debugConnection then
		debugConnection:Disconnect()
		debugConnection = nil
	end
	if debugFolder then
		debugFolder:Destroy()
		debugFolder = nil
	end
	table.clear(debugVisuals)

	if not enabled then
		return self
	end

	local newDebugFolder = Instance.new('Folder')
	newDebugFolder.Name = 'QuickZone_Debug_Visuals'
	newDebugFolder.Parent = workspace
	debugFolder = newDebugFolder

	local function updateVisual(id: number, shape: Types.BoundingVolume, color: Color3)
		local box = debugVisuals[id]

		if not box then
			local newBox = Instance.new('BoxHandleAdornment')
			newBox.Name = 'Zone_' .. id
			newBox.Adornee = workspace.Terrain
			newBox.Transparency = Config.Debug.transparency
			newBox.AlwaysOnTop = true
			newBox.ZIndex = 1
			newBox.Parent = debugFolder
			debugVisuals[id] = newBox
			box = newBox
		end

		box.Size = shape.halfSize * 2
		box.CFrame = shape.cframe
		box.Color3 = color
	end

	debugConnection = RunService.PreRender:Connect(function()
		if not debugFolder then
			return
		end

		-- Draw static zones
		for id, shape in staticShapes do
			if not debugVisuals[id] then
				local isActive = State.zoneAttachedObservers[id] ~= nil
				local color = isActive and Config.Debug.staticActive or Config.Debug.staticInactive
				updateVisual(id, shape, color)
			end
		end

		-- Draw dynamic zones
		for id, zone in dynamicShapes do
			local isActive = State.zoneAttachedObservers[id] ~= nil
			local color = isActive and Config.Debug.dynamicActive or Config.Debug.dynamicInactive
			updateVisual(id, zone, color)
		end

		-- Destroy removed zones
		for id, box in debugVisuals do
			if not staticShapes[id] and not dynamicShapes[id] then
				box:Destroy()
				debugVisuals[id] = nil
			end
		end
	end)

	return self
end

return QuickZone
