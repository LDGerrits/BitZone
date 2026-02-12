--!strict

local Players = game:GetService('Players')
local RunService = game:GetService('RunService')

local Geometry = require(script.Parent.Parent.Core.Geometry)
local LinearBVH = require(script.Parent.Parent.Core.LinearBVH)
local State = require(script.Parent.Parent.State)
local Types = require(script.Parent.Parent.Types)

local IS_CLIENT = RunService:IsClient()

local function disconnectObserverFromGroup(observerId: number, group: Types.InternalGroup)
	local safety = group.config.safety

	for _, entity in group.entities do
		local data = group.entityData[entity]

		local oldZoneId = data.activeObserverMemberships[observerId]
		if not oldZoneId then
			continue
		end

		data.activeObserverMemberships[observerId] = nil
		if State.observerTrackingEntities[observerId] then
			State.observerTrackingEntities[observerId][entity] = nil
		end

		local cbs = State.observerExitedCallbacks[observerId]
		if cbs then
			local z = State.zoneIdToZoneObj[oldZoneId]
			local cd = State.entityCustomData[entity] and State.entityCustomData[entity][observerId]
			for _, fn in cbs do
				if safety then
					task.spawn(fn, entity, z, cd)
				else
					fn(entity, z, cd)
				end
			end
		end
	end
end

--[=[ 
	Observers are the logical bridge between Groups and Zones.
	They monitor specific groups and trigger events when entities within those 
	groups enter or exit any zones associated with the observer.

	@class Observer
]=]
local Observer = {}
Observer.__index = Observer

function Observer.new(priority: number?): Types.Observer
	local observer: Types.InternalObserver = setmetatable({
		id = State.nextObserverId,
	}, Observer) :: any

	State.observerPriorityMap[observer.id] = priority or 0
	State.observerEnteredCallbacks[observer.id] = {}
	State.observerExitedCallbacks[observer.id] = {}
	State.observerTrackingEntities[observer.id] = {}
	State.observerIdToObserverObj[observer.id] = observer
	State.observerEnabled[observer.id] = true

	State.nextObserverId += 1
	return observer
end

--[=[ 
	Links this observer to one or more entity groups. The observer will only
	track entities that belong to subscribed groups.

	```lua
	observer:subscribe(QuickZone.PlayerGroup())
	```

	@method subscribe
	@within Observer
	@param ... Group -- The groups to monitor.
	@return Observer
]=]
function Observer.subscribe(self: Types.InternalObserver, ...: Types.InternalGroup): Types.Observer
	for _, group in { ... } do
		local groupId = group.id

		if not State.groupToObservers[groupId] then
			State.groupToObservers[groupId] = {}
		end

		State.groupToObservers[groupId][self.id] = true
	end

	return self
end

--[=[ 
	Stops the observer from monitoring the specified groups.

	@method unsubscribe
	@within Observer
	@param ... Group -- The groups to stop monitoring.
	@return Observer
]=]
function Observer.unsubscribe(self: Types.InternalObserver, ...: Types.InternalGroup): Types.Observer
	for _, group in { ... } do
		disconnectObserverFromGroup(self.id, group)

		local groupId = group.id
		if State.groupToObservers[groupId] then
			State.groupToObservers[groupId][self.id] = nil
		end
	end

	return self
end

--[=[ 
	Fires when any entity from a subscribed group enters a zone attached to this observer.

	```lua
	local disconnect = observer:onEntered(function(entity, zone, customData)
		print(entity.Name .. ' entered ' .. zone.id)
	end)
	```

	@tag Event
	@method onEntered
	@within Observer
	@param callback (entity: Entity, zone: Zone, customData: any?) -> ()
	@return () -> () -- A function that, when called, disconnects the callback.
]=]
function Observer.onEntered(self: Types.InternalObserver, callback): () -> ()
	table.insert(State.observerEnteredCallbacks[self.id], callback)
	return function()
		local i = table.find(State.observerEnteredCallbacks[self.id], callback)
		if i then
			table.remove(State.observerEnteredCallbacks[self.id], i)
		end
	end
end

--[=[ 
	Fires when an entity exits all zones attached to this observer.

	@tag Event
	@method onExited
	@within Observer
	@param callback (entity: Entity, zone: Zone, customData: any?) -> ()
	@return () -> () -- A function that, when called, disconnects the callback.
]=]
function Observer.onExited(self: Types.InternalObserver, callback): () -> ()
	table.insert(State.observerExitedCallbacks[self.id], callback)
	return function()
		local i = table.find(State.observerExitedCallbacks[self.id], callback)
		if i then
			table.remove(State.observerExitedCallbacks[self.id], i)
		end
	end
end

--[=[ 
	Specialized event for Player entities.

	@tag Event
	@method onPlayerEntered
	@within Observer
	@param callback (player: Player, zone: Zone) -> ()
	@return () -> ()
]=]
function Observer.onPlayerEntered(self: Types.InternalObserver, callback: (Player, Types.Zone) -> ()): () -> ()
	return self:onEntered(function(_entity, zone, data: { Player: Player }?)
		if data and data.Player then
			callback(data.Player, zone)
		end
	end)
end

--[=[ 
	A specialized event for Player entities. Fires when a player's character 
	exits all zones attached to this observer.

	@tag Event
	@method onPlayerExited
	@within Observer
	@param callback (player: Player, zone: Zone) -> ()
	@return () -> () -- A function to disconnect the callback.
]=]
function Observer.onPlayerExited(self: Types.InternalObserver, callback: (Player, Types.Zone) -> ()): () -> ()
	return self:onExited(function(_entity, zone, data: { Player: Player }?)
		if data and data.Player then
			callback(data.Player, zone)
		end
	end)
end

--[=[ 
	Specialized event for the LocalPlayer.

	@client
	@tag Event
	@method onLocalPlayerEntered
	@within Observer
	@param callback (zone: Zone) -> ()
	@return () -> ()
]=]
function Observer.onLocalPlayerEntered(self: Types.InternalObserver, callback: (Types.Zone) -> ()): () -> ()
	assert(IS_CLIENT, '[QuickZone] Observer:onLocalPlayerEntered can only be called on the Client.')
	return self:onEntered(function(_entity, zone, data: { Player: Player }?)
		if data and data.Player == Players.LocalPlayer then
			callback(zone)
		end
	end)
end

--[=[ 
	A specialized event for the LocalPlayer. Fires when the local player's 
	character exits all zones attached to this observer.

	@client
	@tag Event
	@method onLocalPlayerExited
	@within Observer
	@param callback (zone: Zone) -> ()
	@return () -> ()
]=]
function Observer.onLocalPlayerExited(self: Types.InternalObserver, callback: (Types.Zone) -> ()): () -> ()
	assert(IS_CLIENT, '[QuickZone] Observer:onLocalPlayerExited can only be called on the Client.')
	return self:onExited(function(_entity, zone, data: { Player: Player }?)
		if data and data.Player == Players.LocalPlayer then
			callback(zone)
		end
	end)
end

--[=[ 
	Enables or disables the observer. When disabled, it will no longer process
	spatial checks or fire events.

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
	State.isDirty = true

	if enabled then
		return self
	end

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

	return self
end

--[=[ 
	Updates the resolution priority of the observer.
	@method setPriority
	@within Observer
	@param p number
	@return Observer
]=]
function Observer.setPriority(self: Types.InternalObserver, p: number): Types.Observer
	State.observerPriorityMap[self.id] = p
	State.isDirty = true
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
	Checks if a specific player's character is currently inside a zone 
	attached to this observer.

	@method isPlayerInside
	@within Observer
	@param player Player
	@return boolean
]=]
function Observer.isPlayerInside(self: Types.InternalObserver, player: Player): boolean
	local character = player.Character
	if not character then
		return false
	end

	local hrp = character:FindFirstChild('HumanoidRootPart') :: BasePart?
	if not hrp then
		return false
	end

	return self:isEntityInside(hrp)
end

--[=[ 
	Checks if the local player's character is currently inside a zone 
	attached to this observer.

	@client
	@method isLocalPlayerInside
	@within Observer
	@return boolean
]=]
function Observer.isLocalPlayerInside(self: Types.InternalObserver): boolean
	if not IS_CLIENT then
		error('[QuickZone] Observer:isLocalPlayerInside can only be called on the Client.', 2)
	end

	return self:isPlayerInside(Players.LocalPlayer)
end

--[=[ 
	Checks if a specific entity is currently inside a zone attached to this observer.
	@method isEntityInside
	@within Observer
	@param entity Entity
	@return boolean
]=]
function Observer.isEntityInside(self: Types.InternalObserver, entity: Types.Entity): boolean
	local groupId = State.entityToGroup[entity]
	if not groupId then
		return false
	end

	local group = State.groups[groupId]
	local data = group.entityData[entity]
	if not data then
		return false
	end

	return data.activeObserverMemberships[self.id] ~= nil
end

--[=[ 
	Checks if a specific point in world space is inside any zone attached to this observer.
	
	@method isPointInside
	@within Observer
	@param position Vector3
	@return boolean
]=]
function Observer.isPointInside(self: Types.InternalObserver, position: Vector3): boolean
	local isInside = false

	if State.dynamicRootNode then
		LinearBVH.queryPoint(State.dynamicRootNode, position, function(zoneId)
			if isInside then
				return
			end
			local observers = State.zoneAttachedObservers[zoneId]
			if observers and table.find(observers, self.id) then
				if Geometry.isPointInShape(position, State.dynamicShapes[zoneId]) then
					isInside = true
				end
			end
		end)

		if isInside then
			return true
		end
	end

	if State.staticRootNode then
		LinearBVH.queryPoint(State.staticRootNode, position, function(zoneId)
			if isInside then
				return
			end
			local observers = State.zoneAttachedObservers[zoneId]
			if observers and table.find(observers, self.id) then
				if Geometry.isPointInShape(position, State.staticShapes[zoneId]) then
					isInside = true
				end
			end
		end)
	end

	return isInside
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
	return State.observerPriorityMap[self.id] or 0
end

--[=[ 
	Returns a list of all tracked entities currently inside zones attached to this observer.
	@method getEntitiesInside
	@within Observer
	@return { Entity }
]=]
function Observer.getEntitiesInside(self: Types.InternalObserver): { Types.Entity }
	local entities = State.observerTrackingEntities[self.id]
	if not entities then
		return {}
	end
	local results = {}
	for entity, _ in entities do
		table.insert(results, entity)
	end
	return results
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
	Cleans up the observer, disables tracking, and unsubscribes it from all groups and zones.
	
	@tag Destructor
	@method destroy
	@within Observer
]=]
function Observer.destroy(self: Types.InternalObserver): ()
	self:setEnabled(false)

	local id = self.id
	for _, observers in State.groupToObservers do
		observers[id] = nil
	end

	for _, attachedList in State.zoneAttachedObservers do
		local idx = table.find(attachedList, id)
		while idx do
			table.remove(attachedList, idx)
			idx = table.find(attachedList, id)
		end
	end

	State.observerPriorityMap[id] = nil
	State.observerEnteredCallbacks[id] = nil
	State.observerExitedCallbacks[id] = nil
	State.observerTrackingEntities[id] = nil
	State.observerIdToObserverObj[id] = nil
	State.observerEnabled[id] = nil

	State.isDirty = true
	setmetatable(self :: any, nil)
end

return Observer
