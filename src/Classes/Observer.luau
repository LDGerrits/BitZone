--!strict

local Players = game:GetService('Players')
local RunService = game:GetService('RunService')

local Geometry = require(script.Parent.Parent.Core.Geometry)
local LinearBVH = require(script.Parent.Parent.Core.LinearBVH)
local State = require(script.Parent.Parent.State)
local Types = require(script.Parent.Parent.Types)

local IS_CLIENT = RunService:IsClient()

local Observer = {}
Observer.__index = Observer

function Observer.new(priority: number?): Types.Observer
	local observer = (
		setmetatable({
			id = State.nextObserverId,
			_mainConnections = {},
			_playerTrackers = {},
		}, Observer) :: any
	) :: Types.Observer

	State.ObserverPriorityMap[observer.id] = priority or 0
	State.observerEnteredCallbacks[observer.id] = {}
	State.observerExitedCallbacks[observer.id] = {}
	State.observerTrackingEntities[observer.id] = {}
	State.observerIdToObserverObj[observer.id] = observer

	State.nextObserverId += 1
	return observer
end

function Observer:setPriority(p: number): Types.Observer
	State.ObserverPriorityMap[self.id] = p
	State.isDirty = true
	return self
end

function Observer:subscribe(...: Types.Group): Types.Observer
	for _, group in { ... } do
		local groupId = group.id

		if not State.groupToObservers[groupId] then
			State.groupToObservers[groupId] = {}
		end

		State.groupToObservers[groupId][self.id] = true
	end

	return self
end

function Observer:unsubscribe(...: Types.Group): Types.Observer
	for _, group in { ... } do
		local groupId = group.id
		if State.groupToObservers[groupId] then
			State.groupToObservers[groupId][self.id] = nil
		end

		local safety = group._config.safety
		for _, entity in group._entities do
			local data = group._entityData[entity]
			local oldZoneId = data and data.activeObserverMemberships[self.id]
			if oldZoneId then
				data.activeObserverMemberships[self.id] = nil
				if State.observerTrackingEntities[self.id] then
					State.observerTrackingEntities[self.id][entity] = nil
				end

				local cbs = State.observerExitedCallbacks[self.id]
				if cbs then
					local z = State.zoneIdToZoneObj[oldZoneId]
					local cd = State.entityCustomData[entity] and State.entityCustomData[entity][self.id]
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
	end

	return self
end

function Observer:isPlayerInside(player: Player): boolean
	local character = player.Character
	if not character then
		return false
	end

	local hrp = character:FindFirstChild('HumanoidRootPart')
	if not hrp then
		return false
	end

	return self:isEntityInside(hrp)
end

function Observer:isLocalPlayerInside(): boolean
	if not IS_CLIENT then
		error('[QuickZone] isLocalPlayerInside can only be called on the Client.', 2)
	end

	return self:isPlayerInside(Players.LocalPlayer)
end

function Observer:isEntityInside(entity: Types.Entity): boolean
	local groupId = State.entityToGroup[entity]
	if not groupId then
		return false
	end

	local group = State.groups[groupId]
	local data = group._entityData[entity]
	if not data then
		return false
	end

	return data.activeObserverMemberships[self.id] ~= nil
end

function Observer:isPointInside(position: Vector3): boolean
	if not State.rootNode then
		return false
	end

	local isInside = false
	LinearBVH.queryPoint(State.rootNode, position, function(zoneId)
		if isInside then
			return
		end
		local observers = State.zoneAttachedObservers[zoneId]
		if observers and table.find(observers, self.id) then
			if Geometry.isPointInShape(position, State.objects[zoneId]) then
				isInside = true
			end
		end
	end)

	return isInside
end

function Observer:getEntitiesInside(): { Types.Entity }
	local entities = State.observerTrackingEntities[self.id]
	if not entities then
		return {}
	end
	local results = {}
	for entity, _ in pairs(entities) do
		table.insert(results, entity)
	end
	return results
end

function Observer:getEntities(): { Types.Entity }
	local results = {}
	for groupId, observers in pairs(State.groupToObservers) do
		if observers[self.id] then
			local group = State.groups[groupId]
			for _, entity in ipairs(group._entities) do
				table.insert(results, entity)
			end
		end
	end
	return results
end

function Observer:getZones(): { Types.Zone }
	local results = {}
	for zoneId, attachedList in pairs(State.zoneAttachedObservers) do
		if table.find(attachedList, self.id) then
			local zone = State.zoneIdToZoneObj[zoneId]
			if zone then
				table.insert(results, zone)
			end
		end
	end
	return results
end

function Observer:getGroups(): { Types.Group }
	local result = {}

	for groupId, observersMap in pairs(State.groupToObservers) do
		if observersMap[self.id] then
			local group = State.groups[groupId]
			if group then
				table.insert(result, group)
			end
		end
	end

	return result
end

function Observer:onEntered(callback): () -> ()
	table.insert(State.observerEnteredCallbacks[self.id], callback)
	return function()
		local i = table.find(State.observerEnteredCallbacks[self.id], callback)
		if i then
			table.remove(State.observerEnteredCallbacks[self.id], i)
		end
	end
end

function Observer:onExited(callback): () -> ()
	table.insert(State.observerExitedCallbacks[self.id], callback)
	return function()
		local i = table.find(State.observerExitedCallbacks[self.id], callback)
		if i then
			table.remove(State.observerExitedCallbacks[self.id], i)
		end
	end
end

function Observer:onPlayerEntered(callback: (Player, Types.Zone) -> ()): () -> ()
	return self:onEntered(function(_entity, zone, data: { Player: Player }?)
		if data and data.Player then
			callback(data.Player, zone)
		end
	end)
end

function Observer:onPlayerExited(callback: (Player, Types.Zone) -> ()): () -> ()
	return self:onExited(function(_entity, zone, data: { Player: Player }?)
		if data and data.Player then
			callback(data.Player, zone)
		end
	end)
end

function Observer:onLocalPlayerEntered(callback: (Types.Zone) -> ()): () -> ()
	assert(IS_CLIENT, '[QuickZone] onLocalPlayerEntered can only be called on the Client.')
	return self:onEntered(function(_entity, zone, data: { Player: Player }?)
		if data and data.Player == Players.LocalPlayer then
			callback(zone)
		end
	end)
end

function Observer:onLocalPlayerExited(callback: (Types.Zone) -> ()): () -> ()
	assert(IS_CLIENT, '[QuickZone] onLocalPlayerExited can only be called on the Client.')
	return self:onExited(function(_entity, zone, data: { Player: Player }?)
		if data and data.Player == Players.LocalPlayer then
			callback(zone)
		end
	end)
end

function Observer:destroy(): ()
	local id = self.id
	for _, observers in pairs(State.groupToObservers) do
		observers[id] = nil
	end

	for _, attachedList in pairs(State.zoneAttachedObservers) do
		local idx = table.find(attachedList, id)
		while idx do
			table.remove(attachedList, idx)
			idx = table.find(attachedList, id)
		end
	end

	State.ObserverPriorityMap[id] = nil
	State.observerEnteredCallbacks[id] = nil
	State.observerExitedCallbacks[id] = nil
	State.observerTrackingEntities[id] = nil
	State.observerIdToObserverObj[id] = nil
	State.isDirty = true
	setmetatable(self :: any, nil)
end

return Observer
