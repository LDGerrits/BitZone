--!strict
--v1.4.6 • LDGerrits
--[=[
	@class QuickZone

	A high-performance, physics-free spatial query library for Roblox. Maintain 60 FPS with 1M+ zones.
]=]

local RunService = game:GetService('RunService')

local Types = require(script.Types)
local Config = require(script.Config)
local Scheduler = require(script.Core.Scheduler)
local State = require(script.Core.State)
local Geometry = require(script.Utils.Geometry)
local LinearBVH = require(script.Utils.LinearBVH)

local queryPoint = LinearBVH.queryPoint
local isPointInShape = Geometry.isPointInShape

local zoneAttachedObservers = State.zoneAttachedObservers
local zoneIdToZoneObj = State.zoneIdToZoneObj
local entityData = State.entityData
local observerIdToObserverObj = State.observerIdToObserverObj
local groups = State.groups
local entityToGroups = State.entityToGroups
local entityToReference = State.entityToReference
local referenceToEntity = State.referenceToEntity

local staticCFrames = State.staticCFrames
local staticHalfSizes = State.staticHalfSizes
local staticTypes = State.staticTypes
local dynamicCFrames = State.dynamicCFrames
local dynamicHalfSizes = State.dynamicHalfSizes
local dynamicTypes = State.dynamicTypes
local dynamicTree = State.dynamicTree
local staticTree = State.staticTree

local debugConnection: RBXScriptConnection?
local debugFolder: Folder?

type DebugVisual = {
	adornment: any,
	shape: Types.ShapeType,
}

local debugVisuals = {} :: { [number]: DebugVisual }

export type QuickZone = Types.QuickZone
export type Zone = Types.Zone
export type Zones = Types.Zones
export type Observer<T> = Types.Observer<T>
export type Group<T> = Types.Group<T>
export type Entity = Types.Entity

local QuickZone = {
	Zone = require(script.Classes.Zone) :: Types.ZoneClass,
	Observer = require(script.Classes.Observer) :: Types.ObserverClass,
	Group = require(script.Classes.Group) :: Types.GroupClass,
}

--[=[ 
	Configure the QuickZone settings. 

	```lua
	QuickZone:configure({
		enabled = true,
		autoSyncRate = 10,
		frameBudget = 0.5,
	})
	```

	@tag Chainable
	@method configure
	@within QuickZone
	@param config { enabled: boolean?, autoSyncRate: number?, frameBudget: number? }
	@return QuickZone
]=]
function QuickZone:configure(config: { enabled: boolean?, autoSyncRate: number?, frameBudget: number? }): QuickZone
	if config.enabled ~= nil then
		self:setEnabled(config.enabled)
	end

	if config.autoSyncRate ~= nil then
		self:setAutoSyncRate(config.autoSyncRate)
	end

	if config.frameBudget ~= nil then
		self:setFrameBudget(config.frameBudget)
	end

	return self
end

--[=[ 
	Enables or disables automatic updating. If false, you must call `QuickZone:update(dt)` manually.

	@tag Chainable
	@method setEnabled
	@within QuickZone
	@param enabled boolean
	@return QuickZone
]=]
function QuickZone:setEnabled(enabled: boolean): QuickZone
	Scheduler.setEnabled(enabled)
	return self
end

--[=[ 
	Manually processes the spatial queries and trigger callbacks.
	This is only necessary if you disabled automatic updating.

	@tag Chainable
	@method update
	@within QuickZone
	@param dt number -- Delta time
	@return QuickZone
]=]
function QuickZone:update(dt: number): QuickZone
	Scheduler.update(dt)
	return self
end

--[=[ 
	Sets the automatic sync rate for zones with references. 
	This controls how often QuickZone checks the reference's position and updates the zone accordingly.

	@tag Chainable
	@method setAutoSyncRate
	@within QuickZone
	@param hz number -- Sync frequency in Hz. Set to 0 to disable auto-syncing.
	@return QuickZone	
]=]
function QuickZone:setAutoSyncRate(hz: number): QuickZone
	Scheduler.setAutoSyncRate(hz)
	return self
end

--[=[ 
	Instantly forces the internal trees to rebuild if any zones have been modified.

	This is only necessary if you have made manual changes to zones or references
	and want to ensure the changes take effect immediately. 
	Otherwise, the Scheduler will automatically rebuild the trees on the next update step.

	@tag Chainable
	@method rebuild
	@within QuickZone
	@return QuickZone
]=]
function QuickZone:rebuild(): QuickZone
	Scheduler.rebuildTrees()
	return self
end

--[=[ 
	Set a reference to an entity. If set, the callbacks will now pass the reference instead of the entity.
	
	```lua
	QuickZone:setReference(transformComponent, numberId)

	local entityGroup = QuickZone.Group.new({ Entities = { entityId } })
	local observer = QuickZone.Observer.new({ Groups = {entityGroup} })

	observer:onEnter(function(numberId, zone)
		print(tostring(numberId) .. " entered!")
	end)
	```

	@tag Chainable
	@method setReference
	@within QuickZone
	@param entity Entity
	@param reference any?
	@return QuickZone
]=]
function QuickZone:setReference(entity: Entity, reference: any?): QuickZone
	local oldReference = entityToReference[entity]

	if reference == nil then
		if not (typeof(oldReference) == 'Instance' and oldReference:IsA('Player')) then
			if oldReference then
				referenceToEntity[oldReference] = nil
			end
			entityToReference[entity] = nil
		end
		return self
	end

	if not (typeof(reference) == 'Instance' and reference:IsA('Player')) then
		entityToReference[entity] = reference
		referenceToEntity[reference] = entity
	end

	return self
end

--[=[ 
	Sets the global execution budget for the Scheduler per frame in milliseconds.
	
	The Scheduler will 'dispatch' entity steps until this threshold is reached, 
	at which point it yields until the next frame to prevent render stutter.
	
	Defaults to 1ms.

	```lua
	-- Allow QuickZone to use up to 0.5ms of frame time
	QuickZone:setFrameBudget(0.5)
	```

	@tag Chainable
	@method setFrameBudget
	@within QuickZone
	@param ms number -- Time in milliseconds
	@return QuickZone
]=]
function QuickZone:setFrameBudget(ms: number): QuickZone
	local s = ms / 1000
	Scheduler.setFrameBudget(s)
	return self
end

--[=[
	Instantly and safely removes the entity from QuickZone. 
	It will be removed from all Groups, resolving any active Observers 
	and firing their `onExit` events.

	@tag Chainable
	@method removeEntity
	@within QuickZone
	@param entity any
	@return QuickZone
]=]
function QuickZone:removeEntity(entity: any): QuickZone
	entity = referenceToEntity[entity] or entity

	local groupIds = entityToGroups[entity]
	if not groupIds then
		return self
	end

	local idsToRemove = {}
	for groupId in groupIds do
		table.insert(idsToRemove, groupId)
	end

	for _, groupId in idsToRemove do
		local group = groups[groupId]
		if group then
			group:remove(entity)
		end
	end

	return self
end

--[=[
	Returns the physical Entity associated with the reference.

	@method getEntityOfReference
	@within QuickZone
	@param reference any
	@return Entity?
]=]
function QuickZone:getEntityOfReference(reference: any): Types.Entity?
	local entity = referenceToEntity[reference]
	if entity then
		return entity
	end

	entity = reference
	if typeof(entity) == 'Instance' then
		if
			entity:IsA('BasePart')
			or entity:IsA('Attachment')
			or entity:IsA('Bone')
			or entity:IsA('Camera')
			or entity:IsA('Model')
		then
			return entity
		end
	elseif typeof(entity) == 'table' then
		if entity.Position or entity.CFrame or entity.WorldPosition or entity.GetPivot then
			return entity
		end
	end

	return nil
end

--[=[
	Returns the reference associated with the Entity.

	@method getReferenceOfEntity
	@within QuickZone
	@param reference any
	@return any
]=]
function QuickZone:getReferenceOfEntity(entity: any): any
	return entityToReference[entity] or entity
end

--[=[ 
	Returns an array of all Observers currently existing.

	@method getObservers
	@within QuickZone
	@return { Observer }
]=]
function QuickZone:getObservers(): { Types.Observer<any> }
	local result = {}
	for _, observer in observerIdToObserverObj do
		table.insert(result, observer)
	end
	return (result :: any) :: { Types.Observer<any> }
end

--[=[ 
	Returns an array of all Groups (including PlayerGroups) currently 
	registered.

	@method getGroups
	@within QuickZone
	@return { Group }
]=]
function QuickZone:getGroups(): { Types.Group }
	local result = {}
	for _, group in groups do
		table.insert(result, group)
	end
	return result
end

--[=[ 
	Returns an array containing every Zone currently registered.
	This includes both static and dynamic zones.

	@method getZones
	@within QuickZone
	@return { Zone }
]=]
function QuickZone:getZones(): { Types.Zone }
	local result = {}
	for _, zone in zoneIdToZoneObj do
		table.insert(result, zone)
	end
	return result
end

--[=[ 
	Returns a flattened array of every entity currently 
	being tracked across all Groups.

	@method getEntities
	@within QuickZone
	@return { any }
]=]
function QuickZone:getEntities(): { any }
	local result = {}
	local count = 0

	for entity in entityData do
		count += 1
		result[count] = entityToReference[entity] or entity
	end

	return result
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
	local count = 0

	queryPoint(dynamicTree, position, function(zoneId)
		if isPointInShape(position, dynamicCFrames[zoneId], dynamicHalfSizes[zoneId], dynamicTypes[zoneId]) then
			local zone = zoneIdToZoneObj[zoneId]
			if zone then
				count += 1
				results[count] = zone
			end
		end
	end)

	queryPoint(staticTree, position, function(zoneId)
		if isPointInShape(position, staticCFrames[zoneId], staticHalfSizes[zoneId], staticTypes[zoneId]) then
			local zone = zoneIdToZoneObj[zoneId]
			if zone then
				count += 1
				results[count] = zone
			end
		end
	end)

	return results
end

--[=[ 
	Returns an array of all Zones the given entity is actively inside, 
	based on its observer memberships.

	@method getZonesOfEntity
	@within QuickZone
	@param entity any
	@return { Zone }
]=]
function QuickZone:getZonesOfEntity(entity: any): { Types.Zone }
	entity = referenceToEntity[entity] or entity
	local data = entityData[entity]
	if not data or not data.activeObserverMemberships then
		return {}
	end

	local results = {}
	local seenZones = {} -- In case multiple observers track the entity in the same zone

	for _, zoneId in data.activeObserverMemberships do
		if seenZones[zoneId] then
			continue
		end
		seenZones[zoneId] = true

		local zone = zoneIdToZoneObj[zoneId]
		if zone then
			table.insert(results, zone)
		end
	end

	return results
end

--[=[ 
	Returns an array of all Groups that the specified entity is currently in.

	@method getGroupsOfEntity
	@within QuickZone
	@param entity any
	@return { Group }
]=]
function QuickZone:getGroupsOfEntity(entity: any): { Types.Group }
	entity = referenceToEntity[entity] or entity
	local groupIds = entityToGroups[entity]
	if not groupIds then
		return {}
	end

	local results = {}
	local count = 0

	for groupId in groupIds do
		local group = groups[groupId]
		if group then
			count += 1
			results[count] = group
		end
	end

	return results
end

--[=[
	Returns a zero-allocation iterator for all Groups.

	@method iterGroups
	@within QuickZone
	@return () -> Group?
]=]
function QuickZone:iterGroups(): () -> Types.Group?
	local groupId: number? = nil
	return function(): Types.Group?
		groupId = next(groups, groupId)
		return groupId and groups[groupId] or nil
	end
end

--[=[
	Returns a zero-allocation iterator for all Zones.

	@method iterZones
	@within QuickZone
	@return () -> Zone?
]=]
function QuickZone:iterZones(): () -> Types.Zone?
	local zoneId: number? = nil

	return function(): Types.Zone?
		zoneId = next(zoneIdToZoneObj, zoneId)
		return zoneId and zoneIdToZoneObj[zoneId] or nil
	end
end

--[=[
	Returns a zero-allocation iterator for all entities.

	@method iterEntities
	@within QuickZone
	@return () -> any?
]=]
function QuickZone:iterEntities(): () -> any?
	local entity: Types.Entity? = nil

	return function(): any?
		entity = next(entityData, entity)
		if entity then
			return entityToReference[entity] or entity
		end
		return entity
	end
end

--[=[
	Returns a zero-allocation iterator for all Observers.

	@method iterObservers
	@within QuickZone
	@return () -> Observer?
]=]
function QuickZone:iterObservers(): () -> Types.Observer<any>?
	local observerId: number? = nil

	return function(): Types.Observer<any>?
		observerId = next(observerIdToObserverObj, observerId)
		return observerId and observerIdToObserverObj[observerId] or nil
	end
end

--[=[ 
	Returns a zero-allocation iterator for all Groups that the specified entity is currently in.

	@method iterGroupsOfEntity
	@within QuickZone
	@param entity any
	@return () -> Group?
]=]
function QuickZone:iterGroupsOfEntity(entity: any): () -> Types.Group?
	entity = referenceToEntity[entity] or entity

	local groupIds = entityToGroups[entity]
	if not groupIds then
		return function()
			return nil
		end
	end

	local groupId: number? = nil
	return function(): Types.Group?
		groupId = next(groupIds, groupId)
		return groupId and groups[groupId] or nil
	end
end

--[=[ 
	Returns an iterator for all unique Zones the given entity is actively inside.

	@method iterZonesOfEntity
	@within QuickZone
	@param entity any
	@return () -> Zone?
]=]
function QuickZone:iterZonesOfEntity(entity: any): () -> Types.Zone?
	entity = referenceToEntity[entity] or entity

	local data = entityData[entity]
	if not data or not data.activeObserverMemberships then
		return function()
			return nil
		end
	end

	local memberships = data.activeObserverMemberships
	local seenZones: { [number]: boolean } = {}
	local observerId: number?

	return function(): Types.Zone?
		while true do
			observerId = next(memberships, observerId)
			if not observerId then
				return nil
			end

			local zoneId = memberships[observerId :: number]
			if seenZones[zoneId] then
				continue
			end

			seenZones[zoneId] = true
			local zone = zoneIdToZoneObj[zoneId]

			if zone then
				return zone
			end
		end
	end
end

--[=[
	Returns an iterator that returns every Zone intersecting the given point.
	Ideal for zero-allocation ECS queries. Safe to `break` out of early.

	@method iterZonesAtPoint
	@within QuickZone
	@param point Vector3
	@return () -> Zone?
]=]
function QuickZone:iterZonesAtPoint(point: Vector3): () -> Types.Zone?
	local dynamicNodes = dynamicTree.nodes
	local dynamicCount = dynamicTree.count or 0

	local staticNodes = staticTree.nodes
	local staticCount = staticTree.count or 0

	local px, py, pz = point.X, point.Y, point.Z

	local index = 1
	local checkingDynamic = true

	return function(): Types.Zone?
		if checkingDynamic then
			while index <= dynamicCount do
				local node = dynamicNodes[index]
				local min, max = node.min, node.max

				if px < min.X or px > max.X or py < min.Y or py > max.Y or pz < min.Z or pz > max.Z then
					index = node.skipIndex
					continue
				end

				index += 1
				local hitId = node.id

				if
					hitId > 0
					and isPointInShape(point, dynamicCFrames[hitId], dynamicHalfSizes[hitId], dynamicTypes[hitId])
				then
					return zoneIdToZoneObj[hitId]
				end
			end

			checkingDynamic = false
			index = 1
		end

		if not checkingDynamic then
			while index <= staticCount do
				local node = staticNodes[index]
				local min, max = node.min, node.max

				if px < min.X or px > max.X or py < min.Y or py > max.Y or pz < min.Z or pz > max.Z then
					index = node.skipIndex
					continue
				end

				index += 1
				local hitId = node.id

				if
					hitId > 0
					and isPointInShape(point, staticCFrames[hitId], staticHalfSizes[hitId], staticTypes[hitId])
				then
					return zoneIdToZoneObj[hitId]
				end
			end
		end

		return nil
	end
end

--[=[ 
	Enables or disables visual rendering of all registered Zones.
	Static and Dynamic zones are colored differently based on their active status.

	@tag Chainable
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

	local function getOrCreateVisual(id: number): DebugVisual
		local visual = debugVisuals[id]
		local zone = zoneIdToZoneObj[id]
		local shape = zone:getShape()

		if visual and visual.shape ~= shape then
			visual.adornment:Destroy()
			debugVisuals[id] = nil
		end

		if not visual then
			local adornment: any
			if shape == 'Ball' then
				adornment = Instance.new('SphereHandleAdornment')
			elseif shape == 'Cylinder' then
				adornment = Instance.new('CylinderHandleAdornment')
			else
				adornment = Instance.new('BoxHandleAdornment')
			end
			adornment.Name = 'Zone_' .. id
			adornment.Adornee = workspace.Terrain
			adornment.Transparency = Config.Debug.transparency
			adornment.AlwaysOnTop = true
			adornment.ZIndex = 1
			adornment.Parent = debugFolder
			visual = {
				adornment = adornment,
				shape = shape,
			}
			debugVisuals[id] = visual
		end
		return visual
	end

	local loopEvent: RBXScriptSignal<number> = RunService:IsClient() and RunService.PreRender or RunService.Heartbeat

	debugConnection = loopEvent:Connect(function()
		if not debugFolder then
			return
		end

		-- Draw static zones
		for id, cframe in staticCFrames do
			local visual = getOrCreateVisual(id)
			local box = visual.adornment
			local halfSize = staticHalfSizes[id]
			local size = halfSize * 2

			local observers = zoneAttachedObservers[id]
			local isActive = observers and next(observers) ~= nil
			local color = isActive and Config.Debug.staticActive or Config.Debug.staticInactive

			if visual.shape == 'Ball' then
				box.Radius = math.max(halfSize.X, halfSize.Y, halfSize.Z)
				box.CFrame = cframe
			elseif visual.shape == 'Cylinder' then
				box.Radius = math.max(halfSize.X, halfSize.Z)
				box.Height = size.X
				box.CFrame = cframe * CFrame.Angles(0, math.rad(90), 0)
			else
				box.Size = size
				box.CFrame = cframe
			end
			box.Color3 = color
		end

		-- Draw dynamic zones
		for id, cframe in dynamicCFrames do
			local visual = getOrCreateVisual(id)
			local box = visual.adornment
			local halfSize = dynamicHalfSizes[id]
			local size = halfSize * 2

			local observers = zoneAttachedObservers[id]
			local isActive = observers and next(observers) ~= nil
			local color = isActive and Config.Debug.dynamicActive or Config.Debug.dynamicInactive

			if visual.shape == 'Ball' then
				box.Radius = math.max(halfSize.X, halfSize.Y, halfSize.Z)
				box.CFrame = cframe
			elseif visual.shape == 'Cylinder' then
				box.Radius = math.max(halfSize.X, halfSize.Z)
				box.Height = size.X
				box.CFrame = cframe * CFrame.Angles(0, math.rad(90), 0)
			else
				box.Size = size
				box.CFrame = cframe
			end
			box.Color3 = color
		end

		-- Destroy removed zones
		for id, box in debugVisuals do
			if not staticCFrames[id] and not dynamicCFrames[id] then
				box.adornment:Destroy()
				debugVisuals[id] = nil
			end
		end
	end)

	return self
end

return QuickZone
