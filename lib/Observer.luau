--!strict

local Players = game:GetService('Players')
local RunService = game:GetService('RunService')

local Geometry = require(script.Parent.Geometry)
local LinearBVH = require(script.Parent.LinearBVH)
local State = require(script.Parent.State)
local Types = require(script.Parent.Types)

local IS_CLIENT = RunService:IsClient()

local Observer = {}
Observer.__index = Observer

function Observer.new(priority: number?): Types.Observer
	local observer = (
		setmetatable({
			Id = State.NextObserverId,
			_mainConnections = {},
			_playerTrackers = {},
		}, Observer) :: any
	) :: Types.Observer

	State.ObserverPriorityMap[observer.Id] = priority or 0
	State.ObserverEnteredCallbacks[observer.Id] = {}
	State.ObserverExitedCallbacks[observer.Id] = {}
	State.ObserverTrackingEntities[observer.Id] = {}
	State.ObserverIdToObserverObj[observer.Id] = observer

	State.NextObserverId += 1
	return observer
end

function Observer:SetPriority(p: number): Types.Observer
	State.ObserverPriorityMap[self.Id] = p
	State.IsDirty = true
	return self
end

function Observer:Track(group: Types.Group): Types.Observer
	local groupId = group.Id
	if not State.GroupToObservers[groupId] then
		State.GroupToObservers[groupId] = {}
	end
	State.GroupToObservers[groupId][self.Id] = true
	return self
end

function Observer:Untrack(group: Types.Group): Types.Observer
	local groupId = group.Id
	if State.GroupToObservers[groupId] then
		State.GroupToObservers[groupId][self.Id] = nil
	end

	local safetyMode = group._config.SafetyMode
	for _, entity in group._entities do
		local data = group._entityData[entity]
		local oldZoneId = data and data.ActiveObserverMemberships[self.Id]
		if oldZoneId then
			data.ActiveObserverMemberships[self.Id] = nil
			State.ObserverTrackingEntities[self.Id][entity] = nil

			local z = State.ZoneIdToZoneObj[oldZoneId]
			local cbs = State.ObserverExitedCallbacks[self.Id]
			if cbs then
				local cd = State.EntityCustomData[entity] and State.EntityCustomData[entity][self.Id]
				for _, fn in cbs do
					if safetyMode then
						task.spawn(fn, entity, z, cd)
					else
						fn(entity, z, cd)
					end
				end
			end
		end
	end

	return self
end

function Observer:IsPlayerInside(player: Player): boolean
	local character = player.Character
	if not character then
		return false
	end

	local hrp = character:FindFirstChild('HumanoidRootPart')
	if not hrp then
		return false
	end

	return self:IsEntityInside(hrp)
end

function Observer:IsLocalPlayerInside(): boolean
	if not IS_CLIENT then
		error('[BitZone] IsLocalPlayerInside can only be called on the Client.', 2)
	end

	return self:IsPlayerInside(Players.LocalPlayer)
end

function Observer:IsEntityInside(entity: Types.Entity): boolean
	local groupId = State.EntityToGroup[entity]
	if not groupId then
		return false
	end

	local group = State.Groups[groupId]
	local data = group._entityData[entity]
	if not data then
		return false
	end

	return data.ActiveObserverMemberships[self.Id] ~= nil
end

function Observer:IsPointInside(position: Vector3): boolean
	if not State.RootNode then
		return false
	end

	local isInside = false
	LinearBVH.QueryPoint(State.RootNode, position, function(zoneId)
		if isInside then
			return
		end
		local observers = State.ZoneBoundObservers[zoneId]
		if observers and table.find(observers, self.Id) then
			if Geometry.IsPointInShape(position, State.Objects[zoneId]) then
				isInside = true
			end
		end
	end)

	return isInside
end

function Observer:GetEntitiesInside(): { Types.Entity }
	local entities = State.ObserverTrackingEntities[self.Id]
	if not entities then
		return {}
	end
	local results = {}
	for entity, _ in pairs(entities) do
		table.insert(results, entity)
	end
	return results
end

function Observer:GetEntities(): { Types.Entity }
	local results = {}
	for groupId, observers in pairs(State.GroupToObservers) do
		if observers[self.Id] then
			local group = State.Groups[groupId]
			for _, entity in ipairs(group._entities) do
				table.insert(results, entity)
			end
		end
	end
	return results
end

function Observer:GetZones(): { Types.Zone }
	local results = {}
	for zoneId, boundList in pairs(State.ZoneBoundObservers) do
		if table.find(boundList, self.Id) then
			local zone = State.ZoneIdToZoneObj[zoneId]
			if zone then
				table.insert(results, zone)
			end
		end
	end
	return results
end

function Observer:GetGroups(): { Types.Group }
	local result = {}

	for groupId, observersMap in pairs(State.GroupToObservers) do
		if observersMap[self.Id] then
			local group = State.Groups[groupId]
			if group then
				table.insert(result, group)
			end
		end
	end

	return result
end

function Observer:OnEntered(callback): () -> ()
	table.insert(State.ObserverEnteredCallbacks[self.Id], callback)
	return function()
		local i = table.find(State.ObserverEnteredCallbacks[self.Id], callback)
		if i then
			table.remove(State.ObserverEnteredCallbacks[self.Id], i)
		end
	end
end

function Observer:OnExited(callback): () -> ()
	table.insert(State.ObserverExitedCallbacks[self.Id], callback)
	return function()
		local i = table.find(State.ObserverExitedCallbacks[self.Id], callback)
		if i then
			table.remove(State.ObserverExitedCallbacks[self.Id], i)
		end
	end
end

function Observer:OnPlayerEntered(callback: (Player, Types.Zone) -> ()): () -> ()
	return self:OnEntered(function(_entity, zone, data: { Player: Player }?)
		if data and data.Player then
			callback(data.Player, zone)
		end
	end)
end

function Observer:OnPlayerExited(callback: (Player, Types.Zone) -> ()): () -> ()
	return self:OnExited(function(_entity, zone, data: { Player: Player }?)
		if data and data.Player then
			callback(data.Player, zone)
		end
	end)
end

function Observer:OnLocalPlayerEntered(callback: (Types.Zone) -> ()): () -> ()
	assert(IS_CLIENT, '[BitZone] OnLocalPlayerEntered can only be called on the Client.')
	return self:OnEntered(function(_entity, zone, data: { Player: Player }?)
		if data and data.Player == Players.LocalPlayer then
			callback(zone)
		end
	end)
end

function Observer:OnLocalPlayerExited(callback: (Types.Zone) -> ()): () -> ()
	assert(IS_CLIENT, '[BitZone] OnLocalPlayerExited can only be called on the Client.')
	return self:OnExited(function(_entity, zone, data: { Player: Player }?)
		if data and data.Player == Players.LocalPlayer then
			callback(zone)
		end
	end)
end

function Observer:Destroy(): ()
	local id = self.Id
	for _, observers in pairs(State.GroupToObservers) do
		observers[id] = nil
	end

	for _, boundList in pairs(State.ZoneBoundObservers) do
		local idx = table.find(boundList, id)
		while idx do
			table.remove(boundList, idx)
			idx = table.find(boundList, id)
		end
	end

	State.ObserverPriorityMap[id] = nil
	State.ObserverEnteredCallbacks[id] = nil
	State.ObserverExitedCallbacks[id] = nil
	State.ObserverTrackingEntities[id] = nil
	State.ObserverIdToObserverObj[id] = nil
	State.IsDirty = true
	setmetatable(self :: any, nil)
end

return Observer
