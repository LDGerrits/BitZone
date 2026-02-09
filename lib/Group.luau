--!strict
local State = require(script.Parent.State)
local Types = require(script.Parent.Types)
local Config = require(script.Parent.Config)

local STRAT_POS = Config.Strategy.POS
local STRAT_PRIM = Config.Strategy.PRIM
local STRAT_WORLD = Config.Strategy.WORLD
local STRAT_CFRAME = Config.Strategy.CFRAME
local STRAT_PIVOT = Config.Strategy.PIVOT

local Group = {}
Group.__index = Group

function Group.new(config: {
	UpdateRate: number?,
	Precision: number?,
	SafetyMode: boolean?,
}?): Types.Group
	local hz = config and config.UpdateRate
	assert(not hz or hz > 0, '[BitZone] UpdateRate must be greater than 0')

	local n = config and config.Precision
	assert(not n or n >= 0, '[BitZone] Precision must be non-negative')

	local id = State.nextGroupId
	State.nextGroupId += 1

	local updateRate = hz or Config.Scheduler.UpdateRate
	local precision = n or Config.Scheduler.Precision
	local safetyMode = Config.Scheduler.SafetyMode
	if config and config.SafetyMode ~= nil then
		safetyMode = config.SafetyMode
	end

	local self = (
		setmetatable({
			Id = id,
			_entities = {},
			_entityIndices = {},
			_entityData = {},
			_config = {
				UpdateRate = updateRate,
				PrecisionSq = precision ^ 2,
				SafetyMode = safetyMode,
			},
			_lastProcessedIndex = 1,
		}, Group) :: any
	) :: Types.Group

	State.groups[id] = self
	State.groupToObservers[id] = {}

	return self
end

function Group:setConfig(config: {
	UpdateRate: number?,
	Precision: number?,
	SafetyMode: boolean?,
})
	local hz = config.UpdateRate
	assert(not hz or hz > 0, '[BitZone] UpdateRate must be greater than 0')

	local n = config.Precision
	assert(not n or n >= 0, '[BitZone] Precision must be non-negative')

	if hz then
		self._config.UpdateRate = hz
	end
	if n then
		self._config.Precision = n
	end
	if config.SafetyMode ~= nil then
		self._config.SafetyMode = config.SafetyMode
	end
end

function Group:setUpdateRate(hz: number): Types.Group
	assert(hz > 0, '[BitZone] UpdateRate must be greater than 0')

	self._config.UpdateRate = hz

	return self
end

function Group:setPrecision(n: number): Types.Group
	assert(n >= 0, '[BitZone] Precision must be non-negative')

	self._config.PrecisionSq = n ^ 2
	return self
end

function Group:setSafetyMode(enabled: boolean): Types.Group
	self.Con_configfig.SafetyMode = enabled
	return self
end

function Group:add(entity: Types.Entity, customData: any?): Types.Group
	local oldGroupId = State.entityToGroup[entity]
	if oldGroupId then
		if oldGroupId == self.Id then
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
				'[BitZone] add Failed: The provided entity (%s) is not a supported type. '
					.. 'Ensure it is a BasePart, Model, Attachment, Bone, Camera, or a table with a Position/CFrame.',
				tostring(entity)
			),
			2
		)
	end

	local data = {
		LastPosition = Vector3.zero,
		Strategy = strat,
		IsDirty = true,
		ActiveObserverMemberships = {},
	}

	local idx = #self._entities + 1
	self._entities[idx] = entity
	self._entityIndices[entity] = idx
	self._entityData[entity] = data

	State.entityToGroup[entity] = self.Id

	if customData then
		if not State.entityCustomData[entity] then
			State.entityCustomData[entity] = {}
		end
		State.entityCustomData[entity] = customData
	end

	return self
end

function Group:remove(entity: Types.Entity): Types.Group
	if State.entityToGroup[entity] ~= self.Id then
		return self
	end

	local data = self._entityData[entity]

	-- Trigger exit
	local safetyMode = self._config.SafetyMode
	for gId, oldZoneId in pairs(data.ActiveObserverMemberships) do
		if State.observerTrackingEntities[gId] then
			State.observerTrackingEntities[gId][entity] = nil
		end

		local cbs = State.observerExitedCallbacks[gId]
		if cbs then
			local z = State.zoneIdToZoneObj[oldZoneId]
			local cd = State.entityCustomData[entity] and State.entityCustomData[entity][gId]
			for _, fn in cbs do
				if safetyMode then
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

	return self
end

function Group:getEntities(): { Types.Entity }
	local result = table.create(#self._entities)
	table.move(self._entities, 1, #self._entities, 1, result)
	return result
end

function Group:getObservers(): { Types.Observer }
	local result = {}
	local observersMap = State.groupToObservers[self.Id]

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
	UpdateRate: number,
	Precision: number,
	SafetyMode: boolean,
}
	local config = self._config
	return {
		UpdateRate = config.UpdateRate,
		Precision = math.sqrt(config.PrecisionSq),
		SafetyMode = config.SafetyMode,
	}
end

function Group:destroy(): ()
	for i = #self._entities, 1, -1 do
		self:remove(self._entities[i])
	end

	State.groupToObservers[self.Id] = nil
	State.groups[self.Id] = nil
	setmetatable(self :: any, nil)
end

return Group
