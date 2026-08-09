--!strict
--[=[ 
	@class Observer

	Observers are the logical bridge between Groups and Zones.
	They monitor specific groups and trigger events when entities within those 
	groups enter or exit any zones associated with the observer.
]=]

local Players = game:GetService('Players')
local RunService = game:GetService('RunService')

local Config = require(script.Parent.Parent.Config)
local State = require(script.Parent.Parent.Core.State)
local Types = require(script.Parent.Parent.Types)
local Geometry = require(script.Parent.Parent.Utils.Geometry)
local Log = require(script.Parent.Parent.Utils.Log)

local isPointInShape = Geometry.isPointInShape

local hasAttachedMap = {} :: { [number]: boolean }
local hasSubscribedMap = {} :: { [number]: boolean }

local dirtyProfiles = State.dirtyProfiles
local dirtyTopology = State.dirtyTopology
local zoneAttachedObservers = State.zoneAttachedObservers

local staticCFrames = State.staticCFrames
local staticHalfSizes = State.staticHalfSizes
local staticTypes = State.staticTypes
local dynamicCFrames = State.dynamicCFrames
local dynamicHalfSizes = State.dynamicHalfSizes
local dynamicTypes = State.dynamicTypes
local dynamicTree = State.dynamicTree
local staticTree = State.staticTree

local IS_CLIENT = RunService:IsClient()

local function updateAllEntitiesForObserver(observerId: number)
	for groupId, observers in State.groupToObservers do
		if not observers[observerId] then
			continue
		end

		local group = State.groups[groupId]
		if not group then
			continue
		end

		for _, entity in group.entities do
			dirtyProfiles[entity] = true
			dirtyTopology[entity] = true
		end
	end
end

local function disconnectObserverFromGroup(observerId: number, group: Types.InternalGroup)
	local safety = State.observerSafety[observerId]
	local isEnabled = State.observerEnabled[observerId]

	for _, entity in group.entities do
		local data = State.entityData[entity]
		if not data then
			continue
		end

		dirtyProfiles[entity] = true
		dirtyTopology[entity] = true

		local oldZoneId = data.activeObserverMemberships[observerId]
		if not oldZoneId then
			continue
		end

		local stillTracked = false

		if isEnabled then
			for groupId in State.entityToGroups[entity] do
				if State.groupToObservers[groupId] and State.groupToObservers[groupId][observerId] then
					stillTracked = true
					break
				end
			end
		end

		if stillTracked then
			continue
		end

		data.activeObserverMemberships[observerId] = nil
		if State.observerTrackingEntities[observerId] then
			State.observerTrackingEntities[observerId][entity] = nil
		end

		local cbs = State.observerExitedCallbacks[observerId]
		if not cbs then
			continue
		end

		local z = State.zoneIdToZoneObj[oldZoneId]
		local ref = State.entityToReference[entity] or entity
		for _, fn in cbs do
			if safety then
				task.spawn(fn, ref, z, entity)
			else
				fn(ref, z, entity)
			end
		end
	end
end

local Observer = {}
Observer.__index = Observer

--[=[ 
	Creates an Observer. Observers listen for entities subscribed Groups entering or exiting attached Zones.

	```lua
	local observer = QuickZone.Observer.new({
		groups = { enemyGroup, playerGroup } -- Immediately subscribe to these groups
		zones = { damageZone } -- Immediately subscribe to these zones
		priority = 20, -- The priority value is used to resolve overlaps (defaults to 0)
		updateRate = 20, -- Check at 20Hz (defaults to 30)
		precision = 0.5, -- Ignore movement smaller than 0.5 studs (defaults to 0.1)
		enabled = false, -- Observer will not start processing spatial checks (defaults to true)
		safety = false, -- Wrap callbacks in task.spawn (defaults to true)
	})
	```

	:::warning Safety 
	If safety is set to false, any yielding will result in breaking QuickZone.
	Only set it to false if you do not want the overhead of virtual threads.
	:::

	:::info Resolution Priority
	When an entity is inside multiple zones watched by different observers, 
	higher priority observers take complete control.
	:::

	:::note Dynamic Instantiation
	QuickZone will warn you if an Observer is created without groups or zones. 
	To suppress this warning when building observers dynamically, 
	explicitly pass an empty table (`zones = {}`) or instantiate the observer as disabled (`enabled = false`).
	:::

	@tag Constructor
	@tag Chainable
	@param config { groups: { Types.Group }?, zones: { Types.Zone | Types.Zones }?, priority: number?, updateRate: number?, precision: number?, enabled: boolean?, safety: boolean? }?
	@return Observer
]=]
function Observer.new<T>(config: {
	groups: { Types.Group<T> }?,
	zones: { Types.Zone | Types.Zones },
	priority: number?,
	updateRate: number?,
	precision: number?,
	enabled: boolean?,
	safety: boolean?,
}?): Types.Observer
	local id = State.nextObserverId
	State.nextObserverId += 1

	local self: Types.InternalObserver<T> = setmetatable({
		id = id,
	}, Observer) :: any

	State.observerPriorityMap[id] = config and config.priority or 0
	State.observerUpdateRate[id] = config and config.updateRate or Config.Observer.updateRate
	State.observerPrecisionSq[id] = (config and config.precision or Config.Observer.precision) ^ 2

	State.observerEnteredCallbacks[id] = {}
	State.observerExitedCallbacks[id] = {}
	State.observerTransitionedCallbacks[id] = {}
	State.observerTrackingEntities[id] = {}
	State.observerIdToObserverObj[id] = self
	State.observerEnabled[id] = if config and config.enabled ~= nil then config.enabled else true
	State.observerSafety[id] = if config and config.safety ~= nil then config.safety else Config.Observer.safety
	State.observerStaticCount[id] = 0
	State.observerDynamicCount[id] = 0

	hasAttachedMap[id] = false
	hasSubscribedMap[id] = false

	if config and config.zones then
		for _, zone in config.zones do
			self:attach(zone)
		end
	end

	if config and config.groups then
		for _, group in config.groups do
			self:subscribe(group)
		end
	end

	-- If a user passes a table, the warning is suppressed
	local explicitlyPassedZones = config and config.zones ~= nil
	local explicitlyPassedGroups = config and config.groups ~= nil

	local missingZones = not explicitlyPassedZones and not hasAttachedMap[id]
	local missingGroups = not explicitlyPassedGroups and not hasSubscribedMap[id]

	if missingZones or missingGroups then
		local creationTrace = debug.traceback('', 2)

		task.defer(function()
			-- Ensure the observer wasn't destroyed or disabled
			if not State.observerIdToObserverObj[id] or not self:isEnabled() then
				return
			end

			-- Check if :attach() or :subscribe() was used instead
			if missingZones and not hasAttachedMap[id] then
				Log.warn('Observer %d has no attached zones. It will not detect spatial queries.', creationTrace, id)
			end
			if missingGroups and not hasSubscribedMap[id] then
				Log.warn('Observer %d has no subscribed groups. It will not track any entities.', creationTrace, id)
			end
		end)
	end

	return self
end

--[=[ 
	Links this observer to the specified group. The observer will only
	track entities that belong to subscribed groups.

	```lua
	observer:subscribe(playerGroup):subscribe(enemyGroup)
	```

	@tag Chainable
	@method subscribe
	@within Observer
	@param group Group -- The group to monitor.
	@return Observer
]=]
function Observer.subscribe(self: Types.InternalObserver, group: Types.InternalGroup): Types.Observer
	hasSubscribedMap[self.id] = true

	local groupId = group.id
	if not State.groupToObservers[groupId] then
		State.groupToObservers[groupId] = {}
	end
	State.groupToObservers[groupId][self.id] = true

	for _, entity in group.entities do
		dirtyProfiles[entity] = true
		dirtyTopology[entity] = true
	end

	return self
end

--[=[ 
	Stops the observer from monitoring the specified group.

	@tag Chainable
	@method unsubscribe
	@within Observer
	@param group Group -- The group to stop monitoring.
	@return Observer
]=]
function Observer.unsubscribe(self: Types.InternalObserver, group: Types.InternalGroup): Types.Observer
	local groupId = group.id

	if State.groupToObservers[groupId] then
		State.groupToObservers[groupId][self.id] = nil
	end

	disconnectObserverFromGroup(self.id, group)

	return self
end

--[=[ 
	Attaches the Observer to a zone. The observer will begin 
	monitoring this area for entity overlaps.

	```lua
	-- You are also able to chain calls
	observer:attach(zone1)
		:attach(zone2)
		:attach(zone3)
	```

	@tag Chainable
	@method attach
	@within Observer
	@param zone Zone -- The zone to link.
	@return Observer
]=]
function Observer.attach(self: Types.InternalObserver, zone: any)
	hasAttachedMap[self.id] = true
	zone:attach(self)
	return self
end

--[=[ 
	Detaches the Observer from the zone. The observer will begin 
	monitoring this area for entity overlaps.

	@tag Chainable
	@method detach
	@within Observer
	@param zone Zone -- The zone to unlink.
	@return Observer
]=]
function Observer.detach(self: Types.InternalObserver, zone: any)
	zone:detach(self)
	return self
end

--[=[ 
	Observes entities entering and exiting the zone. 
	The callback executes on entry and expects a function to be returned, 
	which is executed on exit.

	```lua
	observer:observe(function(entity, zone)
		print("Entered", entity)
		local highlight = Instance.new("Highlight", entity)

		-- Return cleanup function
		return function()
			print("Exited", entity)
			highlight:Destroy()
		end
	end)
	```

	@method observe
	@within Observer
	@param callback (entity: any, zone: Zone) -> (() -> ())?
	@return () -> () -- Disconnect function
]=]
function Observer.observe(
	self: Types.InternalObserver,
	callback: (any, Types.Zone, Types.Entity) -> (() -> ())?
): () -> ()
	local cleanups = {} :: { [Types.Entity]: () -> () }
	local activeIds = {} :: { [Types.Entity]: number }
	local nextId = 0

	local cleanupEnter = self:onEnter(function(reference, zone, entity: any)
		nextId += 1
		local observerId = nextId
		activeIds[entity] = observerId

		local cleanup = callback(reference, zone, entity)

		if activeIds[entity] ~= observerId then
			if type(cleanup) == 'function' then
				cleanup()
			end
			return
		end

		if type(cleanup) == 'function' then
			cleanups[entity] = cleanup
		end
	end)

	local cleanupExit = self:onExit(function(_, _, entity: any)
		activeIds[entity] = nil

		local cleanup = cleanups[entity]
		if cleanup then
			cleanups[entity] = nil
			cleanup()
		end
	end)

	local function disconnect()
		cleanupEnter()
		cleanupExit()

		table.clear(activeIds)

		for entity, cleanup in cleanups do
			cleanups[entity] = nil
			task.spawn(cleanup)
		end
	end

	local disconnectDestroy = self:onDestroy(disconnect)

	return function()
		disconnectDestroy()
		disconnect()
	end
end

--[=[ 
	Fires when any entity from a subscribed group enters a zone attached to this observer.

	```lua
	local disconnect = observer:onEnter(function(entity, zone)
		print(entity.Name .. ' entered ' .. zone.id)
	end)
	```

	@tag Event
	@method onEnter
	@within Observer
	@param callback (entity: any, zone: Zone) -> ()
	@return () -> () -- Disconnect function
]=]
function Observer.onEnter(self: Types.InternalObserver, callback: (any, Types.Zone, Types.Entity) -> ()): () -> ()
	table.insert(State.observerEnteredCallbacks[self.id], callback)
	return function()
		local idx = table.find(State.observerEnteredCallbacks[self.id], callback)
		if idx then
			table.remove(State.observerEnteredCallbacks[self.id], idx)
		end
	end
end

--[=[ 
	Fires when an entity exits all zones attached to this observer.

	@tag Event
	@method onExit
	@within Observer
	@param callback (entity: any, zone: Zone) -> ()
	@return () -> () -- Disconnect function
]=]
function Observer.onExit(self: Types.InternalObserver, callback: (any, Types.Zone, Types.Entity) -> ()): () -> ()
	table.insert(State.observerExitedCallbacks[self.id], callback)
	return function()
		local idx = table.find(State.observerExitedCallbacks[self.id], callback)
		if idx then
			table.remove(State.observerExitedCallbacks[self.id], idx)
		end
	end
end

--[=[
	Observes players entering and exiting the zone.
	
	```lua
	observer:observePlayer(function(player, zone)
		print(player.Name .. " entered!")
		
		-- Return cleanup (optional)
		return function()
			print(player.Name .. " left!")
		end
	end)
	```

	@method observePlayer
	@within Observer
	@param callback (player: Player, zone: Zone) -> (() -> ())?
	@return () -> () -- Disconnect function
]=]
function Observer.observePlayer(
	self: Types.InternalObserver,
	callback: (Player, Types.Zone, Types.Entity) -> (() -> ())?
): () -> ()
	local cleanups = {} :: { [Types.Entity]: () -> () }
	local activeIds = {} :: { [Types.Entity]: number }
	local nextId = 0

	local cleanupEnter = self:onEnter(function(reference, zone, entity: any)
		if not (typeof(reference) == 'Instance' and reference:IsA('Player')) then
			return
		end

		nextId += 1
		local observerId = nextId
		activeIds[entity] = observerId

		local cleanup = callback(reference, zone, entity)

		if activeIds[entity] ~= observerId then
			if type(cleanup) == 'function' then
				cleanup()
			end
			return
		end

		if type(cleanup) == 'function' then
			cleanups[entity] = cleanup
		end
	end)

	local cleanupExit = self:onExit(function(_, _, entity: any)
		if not activeIds[entity] then
			return
		end

		activeIds[entity] = nil

		local cleanup = cleanups[entity]
		if cleanup then
			cleanups[entity] = nil
			cleanup()
		end
	end)

	local function disconnect()
		cleanupEnter()
		cleanupExit()

		table.clear(activeIds)

		for entity, cleanup in cleanups do
			cleanups[entity] = nil
			task.spawn(cleanup)
		end
	end

	local disconnectDestroy = self:onDestroy(disconnect)

	return function()
		disconnectDestroy()
		disconnect()
	end
end

--[=[ 
	Specialized event for Player entities.

	```lua
	observer:onPlayerEnter(function(player, zone)
		print(player.Name .. " entered safe zone " .. zone:getId())
		
		-- Play a sound
		local sound = workspace.Sounds.SafeZoneEnter:Clone()
		sound.Parent = player.Character.PrimaryPart
		sound:Play()
		game.Debris:AddItem(sound, 2)
	end)
	```

	@tag Event
	@method onPlayerEnter
	@within Observer
	@param callback (player: Player, zone: Zone) -> ()
	@return () -> () -- Disconnect function
]=]
function Observer.onPlayerEnter(
	self: Types.InternalObserver,
	callback: (Player, Types.Zone, Types.Entity) -> ()
): () -> ()
	return self:onEnter(function(reference, zone, entity: any)
		if typeof(reference) == 'Instance' and reference:IsA('Player') then
			callback(reference, zone, entity)
		end
	end)
end

--[=[ 
	A specialized event for Player entities. Fires when a player's character 
	exits all zones attached to this observer.

	@tag Event
	@method onPlayerExit
	@within Observer
	@param callback (player: Player, zone: Zone) -> ()
	@return () -> () -- Disconnect function
]=]
function Observer.onPlayerExit(
	self: Types.InternalObserver,
	callback: (Player, Types.Zone, Types.Entity) -> ()
): () -> ()
	return self:onExit(function(reference, zone, entity: any)
		if typeof(reference) == 'Instance' and reference:IsA('Player') then
			callback(reference, zone, entity)
		end
	end)
end

--[=[
	Observes the LocalPlayer.

	```lua
	observer:observeLocalPlayer(function(zone)
		local blur = Instance.new("BlurEffect", game.Lighting)
		return function()
			blur:Destroy()
		end
	end)
	```

	@client
	@method observeLocalPlayer
	@within Observer
	@param callback (zone: Zone) -> (() -> ())?
	@return () -> () -- Disconnect function
]=]
function Observer.observeLocalPlayer(
	self: Types.InternalObserver,
	callback: (Types.Zone, Types.Entity) -> (() -> ())?
): () -> ()
	if not IS_CLIENT then
		Log.fatal('Observer:observeLocalPlayer can only be called on the Client.', nil)
	end

	local cleanups = {} :: { [Types.Entity]: () -> () }
	local activeIds = {} :: { [Types.Entity]: number }
	local nextId = 0

	local cleanupEnter = self:onEnter(function(reference, zone, entity: any)
		if reference ~= Players.LocalPlayer then
			return
		end

		nextId += 1
		local observerId = nextId
		activeIds[entity] = observerId

		local cleanup = callback(zone, entity)

		if activeIds[entity] ~= observerId then
			if type(cleanup) == 'function' then
				cleanup()
			end
			return
		end

		if type(cleanup) == 'function' then
			cleanups[entity] = cleanup
		end
	end)

	local cleanupExit = self:onExit(function(_, _, entity: any)
		if not activeIds[entity] then
			return
		end

		activeIds[entity] = nil

		local cleanup = cleanups[entity]
		if cleanup then
			cleanups[entity] = nil
			cleanup()
		end
	end)

	local function disconnect()
		cleanupEnter()
		cleanupExit()

		table.clear(activeIds)

		for entity, cleanup in cleanups do
			cleanups[entity] = nil
			task.spawn(cleanup)
		end
	end

	local disconnectDestroy = self:onDestroy(disconnect)

	return function()
		disconnectDestroy()
		disconnect()
	end
end

--[=[ 
	Specialized event for the LocalPlayer.

	```lua
	observer:onLocalPlayerEnter(function(zone)
		print("You entered zone " .. zone:getId())
		
		local char = player.Character
		if char and char:FindFirstChild("Humanoid") then
			char.Humanoid.WalkSpeed = 24
		end
	end)
	```

	@client
	@tag Event
	@method onLocalPlayerEnter
	@within Observer
	@param callback (zone: Zone) -> ()
	@return () -> () -- Disconnect function
]=]
function Observer.onLocalPlayerEnter(self: Types.InternalObserver, callback: (Types.Zone, Types.Entity) -> ()): () -> ()
	if not IS_CLIENT then
		Log.fatal('Observer:onLocalPlayerEnter can only be called on the Client.', nil)
	end

	return self:onEnter(function(reference, zone, entity: any)
		if reference == Players.LocalPlayer then
			callback(zone, entity)
		end
	end)
end

--[=[ 
	A specialized event for the LocalPlayer. Fires when the local player's 
	character exits all zones attached to this observer.

	@client
	@tag Event
	@method onLocalPlayerExit
	@within Observer
	@param callback (zone: Zone) -> ()
	@return () -> () -- Disconnect function
]=]
function Observer.onLocalPlayerExit(self: Types.InternalObserver, callback: (Types.Zone, Types.Entity) -> ()): () -> ()
	if not IS_CLIENT then
		Log.fatal('Observer:onLocalPlayerExit can only be called on the Client.', nil)
	end

	return self:onExit(function(reference, zone, entity: any)
		if reference == Players.LocalPlayer then
			callback(zone, entity)
		end
	end)
end

--[=[ 
	Observes a Group's presence within the observer's zones.
	The callback fires when the first entity of a group enters, and the 
	returned cleanup function fires when the last entity of the group leaves.

	```lua
	observer:observeGroup(function(group, zone)
		print("Group " .. group:getId() .. " has arrived!")
		return function()
			print("Group " .. group:getId() .. " has left entirely.")
		end
	end)
	```

	@method observeGroup
	@within Observer
	@param callback (group: Group, zone: Zone) -> (() -> ())?
	@return () -> () -- Disconnect function
]=]
function Observer.observeGroup(
	self: Types.InternalObserver,
	callback: (Types.Group, Types.Zone, Types.Entity) -> (() -> ())?
): () -> ()
	local activeMembers = {} :: { [number]: { [Types.Entity]: boolean } }
	local cleanups = {} :: { [number]: () -> () }

	return self:observe(function(_, zone, entity: any)
		local groups = State.entityToGroups[entity]
		if not groups then
			return nil
		end

		for groupId, _ in groups do
			local group = State.groups[groupId]
			if not group or not State.groupToObservers[groupId][self.id] then
				continue
			end

			if not activeMembers[groupId] then
				activeMembers[groupId] = {}
			end

			if next(activeMembers[groupId]) == nil then
				activeMembers[groupId][entity] = true
				local groupCleanup = callback(group, zone, entity)
				if typeof(groupCleanup) == 'function' then
					cleanups[groupId] = groupCleanup
				end
			else
				activeMembers[groupId][entity] = true
			end
		end

		return function()
			for groupId, members in activeMembers do
				if not members[entity] then
					continue
				end

				members[entity] = nil
				if next(members) ~= nil then
					continue
				end

				activeMembers[groupId] = nil
				local groupCleanup = cleanups[groupId]
				if groupCleanup then
					groupCleanup()
					cleanups[groupId] = nil
				end
			end
		end
	end)
end

--[=[ 
	Fires when the first member of a Group enters any zone attached to this observer.
	Subsequent entries by other members of the same group will not trigger this event
	until the group has completely exited and re-entered.

	@tag Event
	@method onGroupEnter
	@within Observer
	@param callback (group: Group, zone: Zone) -> ()
	@return () -> () -- Disconnect function
]=]
function Observer.onGroupEnter(
	self: Types.InternalObserver,
	callback: (Types.Group, Types.Zone, Types.Entity) -> ()
): () -> ()
	local activeMembers = {} :: { [number]: { [Types.Entity]: boolean } }

	return self:observe(function(_, zone, entity: any)
		local groups = State.entityToGroups[entity]
		if not groups then
			return nil
		end

		for groupId, _ in groups do
			if not State.groupToObservers[groupId] or not State.groupToObservers[groupId][self.id] then
				continue
			end

			if not activeMembers[groupId] then
				activeMembers[groupId] = {}
			end

			local isFirst = next(activeMembers[groupId]) == nil
			activeMembers[groupId][entity] = true

			if isFirst then
				local group = State.groups[groupId]
				if group then
					callback(group, zone, entity)
				end
			end
		end

		return function()
			for groupId, members in activeMembers do
				if not members[entity] then
					continue
				end

				members[entity] = nil
				if next(members) == nil then
					activeMembers[groupId] = nil
				end
			end
		end
	end)
end

--[=[ 
	Fires when the last remaining member of a Group exits all zones attached to 
	this observer. This is useful for "cleared" states or stopping group-wide effects.

	@tag Event
	@method onGroupExit
	@within Observer
	@param callback (group: Group, zone: Zone) -> ()
	@return () -> () -- Disconnect function
]=]
function Observer.onGroupExit(
	self: Types.InternalObserver,
	callback: (Types.Group, Types.Zone, Types.Entity) -> ()
): () -> ()
	local activeMembers = {} :: { [number]: { [Types.Entity]: boolean } }

	return self:observe(function(_, zone, entity: any)
		local groups = State.entityToGroups[entity]
		if not groups then
			return nil
		end

		for groupId, _ in groups do
			if not State.groupToObservers[groupId] or not State.groupToObservers[groupId][self.id] then
				continue
			end

			if not activeMembers[groupId] then
				activeMembers[groupId] = {}
			end
			activeMembers[groupId][entity] = true
		end

		return function()
			for groupId, members in activeMembers do
				if not members[entity] then
					continue
				end

				members[entity] = nil
				if next(members) == nil then
					activeMembers[groupId] = nil
					local group = State.groups[groupId]
					if group then
						callback(group, zone, entity)
					end
				end
			end
		end
	end)
end

--[=[ 
	Fires when an entity seamlessly transitions from one attached zone to another 
	overlapping attached zone.

	@tag Event
	@method onTransition
	@within Observer
	@param callback (entity: any, newZone: Zone) -> ()
	@return () -> () -- Disconnect function
]=]
function Observer.onTransition(self: Types.InternalObserver, callback: (any, Types.Zone, Types.Entity) -> ()): () -> ()
	table.insert(State.observerTransitionedCallbacks[self.id], callback)

	return function()
		local idx = table.find(State.observerTransitionedCallbacks[self.id], callback)
		if idx then
			table.remove(State.observerTransitionedCallbacks[self.id], idx)
		end
	end
end

--[=[ 
	Specialized event for Player entities transitioning between overlapping zones.
	If `targetPlayer` is provided, the event will only fire for that specific player.
	
	@tag Event
	@method onPlayerTransition
	@within Observer
	@param callback (player: Player, newZone: Zone) -> ()
	@return () -> () -- Disconnect function
]=]
function Observer.onPlayerTransition(
	self: Types.InternalObserver,
	callback: (Player, Types.Zone, Types.Entity) -> ()
): () -> ()
	return self:onTransition(function(reference, newZone, entity: any)
		local player = State.entityToReference[reference] or reference
		if typeof(player) == 'Instance' and player:IsA('Player') then
			callback(player, newZone, entity)
		end
	end)
end

--[=[ 
	Specialized event for the LocalPlayer transitioning between overlapping zones.
	
	@client
	@tag Event
	@method onLocalPlayerTransition
	@within Observer
	@param callback (newZone: Zone) -> ()
	@return () -> () -- Disconnect function
]=]
function Observer.onLocalPlayerTransition(
	self: Types.InternalObserver,
	callback: (Types.Zone, Types.Entity) -> ()
): () -> ()
	if not IS_CLIENT then
		Log.fatal('Observer:onLocalPlayerTransition can only be called on the Client.', nil)
	end

	return self:onTransition(function(reference, newZone, entity: any)
		local player = State.entityToReference[reference] or reference
		if player == Players.LocalPlayer then
			callback(newZone, entity)
		end
	end)
end

--[=[ 
	Enables or disables the observer. When disabled, it will no longer process
	spatial checks or fire events.

	@tag Chainable
	@method setEnabled
	@within Observer
	@param enabled boolean
	@return Observer
]=]
function Observer.setEnabled(self: Types.InternalObserver, enabled: boolean): Types.Observer
	local wasEnabled = self:isEnabled()

	if wasEnabled == enabled then
		return self
	end

	local id = self.id
	State.observerEnabled[id] = enabled
	State.logicVersion += 1

	if not enabled then
		for groupId, observersMap in State.groupToObservers do
			if not observersMap[id] then
				continue
			end

			local group = State.groups[groupId]
			if not group then
				continue
			end

			disconnectObserverFromGroup(id, group)
		end
	end

	updateAllEntitiesForObserver(self.id)

	return self
end

--[=[
	Whether to wrap callbacks in task.spawn (safe) or not (unsafe).

	:::warning Safety 
	If set to unsafe, you are not allowed to yield in the callbacks anymore. If you do, QuickZone will throw errors.
	:::

	@tag Chainable
	@method setSafety
	@within Observer
	@param enabled boolean
	@return Observer
]=]
function Observer.setSafety(self: Types.InternalObserver, enabled: boolean): Types.Observer
	State.observerSafety[self.id] = enabled
	return self
end

--[=[ 
	Updates the resolution priority of the observer.

	@tag Chainable
	@method setPriority
	@within Observer
	@param p number
	@return Observer
]=]
function Observer.setPriority(self: Types.InternalObserver, p: number): Types.Observer
	State.observerPriorityMap[self.id] = p
	State.logicVersion += 1
	return self
end

--[=[ 
	Updates the update frequency for this observer.

	@tag Chainable
	@method setUpdateRate
	@within Observer
	@param hz number
	@return Observer
]=]
function Observer.setUpdateRate(self: Types.InternalObserver, hz: number): Types.Observer
	if hz < 0 then
		Log.fatal('updateRate must be non-negative.', nil)
	end

	State.observerUpdateRate[self.id] = hz
	updateAllEntitiesForObserver(self.id)
	return self
end

--[=[ 
	Updates the precision in studs for this observer.

	@tag Chainable
	@method setPrecision
	@within Observer
	@param n number
	@return Observer
]=]
function Observer.setPrecision(self: Types.InternalObserver, n: number): Types.Observer
	if n < 0 then
		Log.fatal('precision must be non-negative.', nil)
	end

	State.observerPrecisionSq[self.id] = n ^ 2
	updateAllEntitiesForObserver(self.id)
	return self
end

--[=[ 
	Checks if the observer is currently enabled.

	@method isEnabled
	@within Observer
	@return boolean
]=]
function Observer.isEnabled(self: Types.InternalObserver): boolean
	return State.observerEnabled[self.id] ~= false
end

--[=[ 
	Checks if a specific point in world space is inside any zone attached to this observer.
	
	@method isPointInside
	@within Observer
	@param position Vector3
	@return boolean
]=]
function Observer.isPointInside(self: Types.InternalObserver, position: Vector3): boolean
	local px, py, pz = position.X, position.Y, position.Z
	local observerId = self.id

	local nodes = dynamicTree.nodes
	local index = 1
	local count = dynamicTree.count
	while index <= count do
		local node = nodes[index]
		local min, max = node.min, node.max

		if px < min.X or px > max.X or py < min.Y or py > max.Y or pz < min.Z or pz > max.Z then
			index = node.skipIndex
			continue
		end

		local hitId = node.id
		index += 1

		if hitId == 0 then
			continue
		end

		local observers = zoneAttachedObservers[hitId]
		if not observers or not table.find(observers, observerId) then
			continue
		end

		if isPointInShape(position, dynamicCFrames[hitId], dynamicHalfSizes[hitId], dynamicTypes[hitId]) then
			return true
		end
	end

	nodes = staticTree.nodes
	index = 1
	count = staticTree.count
	while index <= count do
		local node = nodes[index]
		local min, max = node.min, node.max

		if px < min.X or px > max.X or py < min.Y or py > max.Y or pz < min.Z or pz > max.Z then
			index = node.skipIndex
			continue
		end

		local hitId = node.id
		index += 1

		if hitId == 0 then
			continue
		end

		local observers = zoneAttachedObservers[hitId]
		if not observers or not table.find(observers, observerId) then
			continue
		end

		if isPointInShape(position, staticCFrames[hitId], staticHalfSizes[hitId], staticTypes[hitId]) then
			return true
		end
	end

	return false
end

--[=[ 
	Checks if the observer wraps callbacks in task.spawn (safe) or not (unsafe).

	@method isSafe
	@within Observer
	@return boolean
]=]
function Observer.isSafe(self: Types.InternalObserver): boolean
	return State.observerSafety[self.id]
end

--[=[ 
	Returns the unique internal ID of the observer.

	@method getId
	@within Observer
	@return number
]=]
function Observer.getId(self: Types.InternalObserver): number
	return self.id
end

--[=[ 
	Returns the current resolution priority.

	@method getPriority
	@within Observer
	@return number
]=]
function Observer.getPriority(self: Types.InternalObserver): number
	return State.observerPriorityMap[self.id]
end

--[=[ 
	Returns the current update frequency for this observer.

	@method getUpdateRate
	@within Observer
	@return number
]=]
function Observer.getUpdateRate(self: Types.InternalObserver): number
	return State.observerUpdateRate[self.id]
end

--[=[ 
	Updates the precision for this observer.

	@method getPrecision
	@within Observer
	@return number
]=]
function Observer.getPrecision(self: Types.InternalObserver): number
	return math.sqrt(State.observerPrecisionSq[self.id])
end

--[=[ 
	Returns a list of all tracked entities currently inside zones attached to this observer.

	@method getEntitiesInside
	@within Observer
	@return { any }
]=]
function Observer.getEntitiesInside(self: Types.InternalObserver): { any }
	local entities = State.observerTrackingEntities[self.id]
	if not entities then
		return {}
	end
	local results = {}
	for entity, _ in entities do
		local ref = State.entityToReference[entity] or entity
		table.insert(results, ref)
	end
	return results
end

--[=[ 
	Returns a list of all players currently inside zones attached to this observer.

	@method getPlayersInside
	@within Observer
	@return { Player }
]=]
function Observer.getPlayersInside(self: Types.InternalObserver): { Player }
	local result = {}
	local entities = State.observerTrackingEntities[self.id]

	for entity in entities do
		local ref = State.entityToReference[entity] or entity
		if typeof(ref) == 'Instance' and ref:IsA('Player') then
			if not table.find(result, ref) then
				table.insert(result, ref)
			end
		end
	end
	return result
end

--[=[ 
	Returns the list of Zones currently attached to this observer.

	@method getZones
	@within Observer
	@return { Zone }
]=]
function Observer.getZones(self: Types.InternalObserver): { Types.Zone }
	local results = {}
	for zoneId, attachedList in State.zoneAttachedObservers do
		if not table.find(attachedList, self.id) then
			continue
		end

		local zone = State.zoneIdToZoneObj[zoneId]
		if zone then
			table.insert(results, zone)
		end
	end
	return results
end

--[=[ 
	Returns the list of Groups currently monitored by this observer.
	
	@method getGroups
	@within Observer
	@return { Group }
]=]
function Observer.getGroups(self: Types.InternalObserver): { Types.Group }
	local result = {}

	for groupId, observersMap in State.groupToObservers do
		if not observersMap[self.id] then
			continue
		end

		local group = State.groups[groupId]
		if group then
			table.insert(result, group)
		end
	end

	return result
end

--[=[ 
	Returns the specific Zone this entity is currently tracked under for this Observer.

	@method getZoneOfEntity
	@within Observer
	@param entity Entity -- The entity to get the zone for
	@return Zone?
]=]
function Observer.getZoneOfEntity(self: Types.InternalObserver, entity: any): Types.Zone?
	entity = State.referenceToEntity[entity] or entity

	local data = State.entityData[entity]
	if not data then
		return nil
	end

	local zoneId = data.activeObserverMemberships[self.id]
	if zoneId then
		return State.zoneIdToZoneObj[zoneId]
	end
	return nil
end

--[=[ 
	Returns the specific Zone a player is currently tracked under for this Observer.

	@method getZoneOfPlayer
	@within Observer
	@param player Player -- The player to get the zone for
	@return Zone?
]=]
function Observer.getZoneOfPlayer(self: Types.InternalObserver, player: Player): Types.Zone?
	return self:getZoneOfEntity(player)
end

--[=[ 
	Returns an array of all entities currently inside a specific zone attached to this observer.

	@method getEntitiesInZone
	@within Observer
	@param zone Zone
	@return { any }
]=]
function Observer.getEntitiesInZone(self: Types.InternalObserver, zone: Types.Zone): { any }
	local results = {}

	for entity in self:iterEntitiesInZone(zone) do
		table.insert(results, entity)
	end

	return results
end

--[=[ 
	Returns an array of all players currently inside a specific zone attached to this observer.

	@method getPlayersInZone
	@within Observer
	@param zone Zone
	@return { Player }
]=]
function Observer.getPlayersInZone(self: Types.InternalObserver, zone: Types.Zone): { Player }
	local results = {}

	for player in self:iterPlayersInZone(zone) do
		table.insert(results, player)
	end

	return results
end

--[=[ 
	Returns a zero-allocation iterator for all Zones currently attached to this observer.

	@method iterZones
	@within Observer
	@return () -> Zone?
]=]
function Observer.iterZones(self: Types.InternalObserver): () -> Types.Zone?
	local zoneId: number?
	local attachedList: { number }
	local observerId = self.id

	return function(): Types.Zone?
		while true do
			zoneId, attachedList = next(zoneAttachedObservers, zoneId)

			if not zoneId then
				return nil
			end

			if not table.find(attachedList :: { number }, observerId) then
				continue
			end

			local zone = State.zoneIdToZoneObj[zoneId :: number]
			if zone then
				return zone
			end
		end
	end
end

--[=[ 
	Returns a zero-allocation iterator for all Groups currently monitored by this observer.

	@method iterGroups
	@within Observer
	@return () -> Group?
]=]
function Observer.iterGroups(self: Types.InternalObserver): () -> Types.Group?
	local groupId: number?
	local observersMap: { [number]: boolean }
	local observerId = self.id

	return function(): Types.Group?
		while true do
			groupId, observersMap = next(State.groupToObservers, groupId)

			if not groupId then
				return nil
			end

			if not observersMap[observerId] then
				continue
			end

			local group = State.groups[groupId :: number]
			if group then
				return group
			end
		end
	end
end

--[=[ 
	Iterates over all entities currently inside zones attached to this observer.
	Yields both the Entity and the specific Zone they are in.

	@method iterEntitiesInside
	@within Observer
	@return () -> (Entity?, Zone?)
]=]
function Observer.iterEntitiesInside(self: Types.InternalObserver): () -> (any?, Types.Zone?)
	local entities = (State.observerTrackingEntities[self.id] or {}) :: { [Types.Entity]: boolean }
	local entity: Types.Entity?
	local observerId = self.id

	return function()
		while true do
			entity = next(entities :: any, entity)
			if not entity then
				return nil
			end

			local data = State.entityData[entity :: Types.Entity]
			if not data then
				continue
			end

			local zoneId = data.activeObserverMemberships[observerId]
			if not zoneId then
				continue
			end

			local ref = State.entityToReference[entity :: Types.Entity] or entity
			return ref, State.zoneIdToZoneObj[zoneId]
		end
	end
end

--[=[ 
	Iterates over all players currently inside zones attached to this observer.
	Yields both the Player and the specific Zone they are in.

	@method iterPlayersInside
	@within Observer
	@return () -> (Player?, Zone?)
]=]
function Observer.iterPlayersInside(self: Types.InternalObserver): () -> (Player?, Types.Zone?)
	local entities = (State.observerTrackingEntities[self.id] or {}) :: { [Types.Entity]: boolean }
	local entity: Types.Entity?
	local observerId = self.id

	return function()
		while true do
			entity = next(entities :: any, entity)
			if not entity then
				return nil, nil
			end

			local data = State.entityData[entity :: Types.Entity]
			if not data then
				continue
			end

			local zoneId = data.activeObserverMemberships[observerId]
			if not zoneId then
				continue
			end

			local ref = State.entityToReference[entity :: Types.Entity] or entity
			if typeof(ref) == 'Instance' and ref:IsA('Player') then
				return ref, State.zoneIdToZoneObj[zoneId]
			end
		end
	end
end

--[=[ 
	Returns a zero-allocation iterator for all entities currently inside a specific zone 
	attached to this observer.

	@method iterEntitiesInZone
	@within Observer
	@param zone Zone
	@return () -> Entity?
]=]
function Observer.iterEntitiesInZone(self: Types.InternalObserver, zone: Types.Zone): () -> Types.Entity?
	local entities = State.observerTrackingEntities[self.id]
	if not entities then
		return function()
			return nil
		end
	end

	local entity: Types.Entity?
	local targetZoneId = zone:getId()
	local observerId = self.id

	return function(): Types.Entity?
		while true do
			entity = next(entities :: any, entity)
			if not entity then
				return nil
			end

			local data = State.entityData[entity :: Types.Entity]

			if not data or data.activeObserverMemberships[observerId] ~= targetZoneId then
				continue
			end

			return State.entityToReference[entity :: Types.Entity] or entity
		end
	end
end

--[=[ 
	Returns a zero-allocation iterator for all players currently inside a specific zone 
	attached to this observer.

	@method iterPlayersInZone
	@within Observer
	@param zone Zone
	@return () -> Player?
]=]
function Observer.iterPlayersInZone(self: Types.InternalObserver, zone: Types.Zone): () -> Player?
	local entities = State.observerTrackingEntities[self.id]
	if not entities then
		return function()
			return nil
		end
	end

	local entity: Types.Entity?
	local targetZoneId = zone:getId()
	local observerId = self.id

	return function(): Player?
		while true do
			entity = next(entities :: any, entity)
			if not entity then
				return nil
			end

			local data = State.entityData[entity :: Types.Entity]

			if not data or data.activeObserverMemberships[observerId] ~= targetZoneId then
				continue
			end

			local ref = State.entityToReference[entity :: Types.Entity] or entity
			if typeof(ref) == 'Instance' and ref:IsA('Player') then
				return ref
			end
		end
	end
end

--[=[ 
	Fires when `destroy()` is called on the observer

	```lua
	local disconnect = myObserver:onDestroy(function()
		print('Observer was destroyed!')
	end)
	```

	@tag Event
	@method onDestroy
	@within Observer
	@param callback () -> ()
	@return () -> () -- Disconnect function
]=]
function Observer.onDestroy(self: Types.InternalObserver, callback: () -> ()): () -> ()
	if not self.onDestroyCallbacks then
		self.onDestroyCallbacks = {}
	end

	table.insert(self.onDestroyCallbacks :: any, callback)

	return function()
		local idx = table.find(self.onDestroyCallbacks :: any, callback)
		if idx then
			table.remove(self.onDestroyCallbacks :: any, idx)
		end
	end
end

--[=[ 
	Cleans up the observer, disables tracking, and unsubscribes it from all groups and zones.
	
	@tag Destructor
	@method destroy
	@within Observer
]=]
function Observer.destroy(self: Types.InternalObserver): ()
	if self.onDestroyCallbacks then
		for _, callback in self.onDestroyCallbacks do
			task.spawn(callback)
		end
		table.clear(self.onDestroyCallbacks)
	end

	self:setEnabled(false)

	local id = self.id
	for _, observers in State.groupToObservers do
		observers[id] = nil
	end

	for _, attachedList in State.zoneAttachedObservers do
		local idx = table.find(attachedList, id)
		if idx then
			local lastIdx = #attachedList
			if idx ~= lastIdx then
				attachedList[idx] = attachedList[lastIdx]
			end
			attachedList[lastIdx] = nil
		end
	end

	State.observerPriorityMap[id] = nil
	State.observerEnteredCallbacks[id] = nil
	State.observerExitedCallbacks[id] = nil
	State.observerTransitionedCallbacks[id] = nil
	State.observerTrackingEntities[id] = nil
	State.observerIdToObserverObj[id] = nil
	State.observerEnabled[id] = nil
	State.observerSafety[id] = nil
	State.observerUpdateRate[id] = nil
	State.observerPrecisionSq[id] = nil
	State.observerStaticCount[id] = nil
	State.observerDynamicCount[id] = nil

	hasAttachedMap[id] = nil
	hasSubscribedMap[id] = nil

	State.logicVersion += 1
	setmetatable(self :: any, nil)
end

return Observer
