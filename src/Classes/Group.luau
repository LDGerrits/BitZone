--!strict

local State = require(script.Parent.Parent.State)
local Types = require(script.Parent.Parent.Types)
local Config = require(script.Parent.Parent.Config)

local STRAT_POS = Config.Strategy.POS
local STRAT_PRIM = Config.Strategy.PRIM
local STRAT_WORLD = Config.Strategy.WORLD
local STRAT_CFRAME = Config.Strategy.CFRAME
local STRAT_PIVOT = Config.Strategy.PIVOT

local Group = {}
Group.__index = Group

function Group.new(config: {
	updateRate: number?,
	precision: number?,
	safety: boolean?,
}?): Types.Group
	local hz = config and config.updateRate
	assert(not hz or hz > 0, '[QuickZone] updateRate must be greater than 0')

	local n = config and config.precision
	assert(not n or n >= 0, '[QuickZone] precision must be non-negative')

	local id = State.nextGroupId
	State.nextGroupId += 1

	local updateRate = hz or Config.Scheduler.updateRate
	local precision = n or Config.Scheduler.precision
	local safety = Config.Scheduler.safety
	if config and config.safety ~= nil then
		safety = config.safety
	end

	local self = (
		setmetatable({
			id = id,
			_entities = {},
			_entityIndices = {},
			_entityData = {},
			_config = {
				updateRate = updateRate,
				PrecisionSq = precision ^ 2,
				safety = safety,
			},
			_lastProcessedIndex = 1,
		}, Group) :: any
	) :: Types.Group

	State.groups[id] = self
	State.groupToObservers[id] = {}

	return self
end

function Group:setConfig(config: {
	updateRate: number?,
	precision: number?,
	safety: boolean?,
})
	local hz = config.updateRate
	assert(not hz or hz > 0, '[QuickZone] updateRate must be greater than 0')

	local n = config.precision
	assert(not n or n >= 0, '[QuickZone] precision must be non-negative')

	if hz then
		self._config.updateRate = hz
	end
	if n then
		self._config.precision = n
	end
	if config.safety ~= nil then
		self._config.safety = config.safety
	end
end

function Group:setUpdateRate(hz: number): Types.Group
	assert(hz > 0, '[QuickZone] updateRate must be greater than 0')

	self._config.updateRate = hz

	return self
end

function Group:setPrecision(n: number): Types.Group
	assert(n >= 0, '[QuickZone] precision must be non-negative')

	self._config.PrecisionSq = n ^ 2
	return self
end

function Group:setSafety(enabled: boolean): Types.Group
	self.Con_configfig.safety = enabled
	return self
end

function Group:add(entity: Types.Entity, customData: any?): Types.Group
	local oldGroupId = State.entityToGroup[entity]
	if oldGroupId then
		if oldGroupId == self.id then
			return self
		end
		local oldGroup = State.groups[oldGroupId]
		if oldGroup then
			oldGroup:remove(entity)
		end
	end

	local strat
	if typeof(entity) == 'Instance' then
		if entity:IsA('BasePart') then
			strat = STRAT_POS
		elseif entity:IsA('Attachment') or entity:IsA('Bone') then
			strat = STRAT_WORLD
		elseif entity:IsA('Camera') then
			strat = STRAT_CFRAME
		elseif entity:IsA('Model') then
			strat = entity.PrimaryPart and STRAT_PRIM or STRAT_PIVOT
		end
	elseif typeof(entity) == 'table' then
		if entity.Position then
			strat = STRAT_POS
		elseif entity.CFrame then
			strat = STRAT_CFRAME
		elseif entity.WorldPosition then
			strat = STRAT_WORLD
		elseif entity.GetPivot then
			strat = STRAT_PIVOT
		end
	end

	if not strat then
		error(
			string.format(
				'[QuickZone] add Failed: The provided entity (%s) is not a supported type. '
					.. 'Ensure it is a BasePart, Model, Attachment, Bone, Camera, or a table with a Position/CFrame.',
				tostring(entity)
			),
			2
		)
	end

	local data = {
		lastPosition = Vector3.zero,
		strategy = strat,
		isDirty = true,
		activeObserverMemberships = {},
	}

	local idx = #self._entities + 1
	self._entities[idx] = entity
	self._entityIndices[entity] = idx
	self._entityData[entity] = data

	State.entityToGroup[entity] = self.id

	if customData then
		if not State.entityCustomData[entity] then
			State.entityCustomData[entity] = {}
		end
		State.entityCustomData[entity] = customData
	end

	return self
end

function Group:remove(...: Types.Entity): Types.Group
	for _, entity in { ... } do
		if State.entityToGroup[entity] ~= self.id then
			continue
		end

		local data = self._entityData[entity]

		-- Trigger exit
		local safety = self._config.safety
		for gId, oldZoneId in pairs(data.activeObserverMemberships) do
			if State.observerTrackingEntities[gId] then
				State.observerTrackingEntities[gId][entity] = nil
			end

			local cbs = State.observerExitedCallbacks[gId]
			if cbs then
				local z = State.zoneIdToZoneObj[oldZoneId]
				local cd = State.entityCustomData[entity] and State.entityCustomData[entity][gId]
				for _, fn in cbs do
					if safety then
						task.spawn(fn, entity, z, cd)
					else
						fn(entity, z, cd)
					end
				end
			end
		end

		-- Swap-remove from Array
		local idx = self._entityIndices[entity]
		local lastIdx = #self._entities
		local lastEntity = self._entities[lastIdx]

		if idx == lastIdx then
			self._entities[lastIdx] = nil
			self._entityIndices[entity] = nil
		else
			self._entities[idx] = lastEntity
			self._entityIndices[lastEntity] = idx
			self._entities[lastIdx] = nil
			self._entityIndices[entity] = nil
		end

		self._entityData[entity] = nil
		State.entityToGroup[entity] = nil
		State.entityCustomData[entity] = nil
	end

	return self
end

function Group:getEntities(): { Types.Entity }
	local result = table.create(#self._entities)
	table.move(self._entities, 1, #self._entities, 1, result)
	return result
end

function Group:getObservers(): { Types.Observer }
	local result = {}
	local observersMap = State.groupToObservers[self.id]

	if observersMap then
		for observerId, _ in pairs(observersMap) do
			local observer = State.observerIdToObserverObj[observerId]
			if observer then
				table.insert(result, observer)
			end
		end
	end

	return result
end

function Group:getConfig(): {
	updateRate: number,
	precision: number,
	safety: boolean,
}
	local config = self._config
	return {
		updateRate = config.updateRate,
		precision = math.sqrt(config.PrecisionSq),
		safety = config.safety,
	}
end

function Group:destroy(): ()
	for i = #self._entities, 1, -1 do
		self:remove(self._entities[i])
	end

	State.groupToObservers[self.id] = nil
	State.groups[self.id] = nil
	setmetatable(self :: any, nil)
end

return Group
