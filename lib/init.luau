--!strict
local Players = game:GetService('Players')
local RunService = game:GetService('RunService')

local Group = require(script.Group)
local Geometry = require(script.Geometry)
local LinearBVH = require(script.LinearBVH)
local Types = require(script.Types)
local State = require(script.State)
local Zone = require(script.Zone)
local Observer = require(script.Observer)
local Scheduler = require(script.Scheduler)

local objects = State.Objects
local zoneBoundObservers = State.ZoneBoundObservers
local observerIdToObserverObj = State.ObserverIdToObserverObj

local IS_CLIENT = RunService:IsClient()

export type BitZone = Types.BitZone
export type Zone = Types.Zone
export type Observer = Types.Observer
export type Group = Types.Group
export type Entity = Types.Entity

local BitZone = {}

function BitZone.newZone(cframe: CFrame, size: Vector3, shape: Types.ShapeType, associatedPart: BasePart?): Zone
	return Zone.new(cframe, size, shape, associatedPart)
end

function BitZone.newZoneFromPart(part: BasePart): Zone
	local shape: Types.ShapeType = 'Block'
	if (part :: any).Shape == Enum.PartType.Ball then
		shape = 'Ball'
	elseif (part :: any).Shape == Enum.PartType.Cylinder then
		shape = 'Cylinder'
	end
	return Zone.new(part.CFrame, part.Size, shape, part)
end

function BitZone.newObserver(priority: number?): Observer
	return Observer.new(priority)
end

function BitZone.newGroup(config: {
	UpdateRate: number?,
	Precision: number?,
	SafetyMode: boolean?,
}?)
	return Group.new(config)
end

-- TODO
function BitZone.playersGroup(config: {
	UpdateRate: number?,
	Precision: number?,
	SafetyMode: boolean?,
}?): Group
	return
end

-- TODO
function BitZone.localPlayerGroup(config: {
	UpdateRate: number?,
	Precision: number?,
	SafetyMode: boolean?,
}?): Group
	assert(IS_CLIENT, '[BitZone] TrackLocalPlayer can only be called on the Client.')

	return
end

function BitZone:SetFrameBudget(n: number): BitZone
	assert(n > 0, '[BitZone] FrameBudget must be greater than 0')

	Scheduler.SetFrameBudget(n)
	return BitZone
end

function BitZone:GetObserversAtPoint(position: Vector3): { Observer }
	local results = {}
	local foundIds = {}

	if State.RootNode then
		LinearBVH.QueryPoint(State.RootNode, position, function(zoneId)
			if Geometry.IsPointInShape(position, objects[zoneId]) then
				local observers = zoneBoundObservers[zoneId]
				if observers then
					for _, id in observers do
						if not foundIds[id] then
							foundIds[id] = true
							local observer = observerIdToObserverObj[id]
							if observer then
								table.insert(results, observer)
							end
						end
					end
				end
			end
		end)
	end
	return results
end

function BitZone:GetGroupOfEntity(entity: Types.Entity): Types.Group?
	local groupId = State.EntityToGroup[entity]
	if groupId then
		return State.Groups[groupId]
	end
	return nil
end

function BitZone:GetZones(): { Types.Zone }
	local result = {}
	for _, zone in pairs(State.ZoneIdToZoneObj) do
		table.insert(result, zone)
	end
	return result
end

function BitZone:GetObservers(): { Types.Observer }
	local result = {}
	for _, observer in pairs(State.ObserverIdToObserverObj) do
		table.insert(result, observer)
	end
	return result
end

function BitZone:GetGroups(): { Types.Group }
	local result = {}
	for _, group in pairs(State.Groups) do
		table.insert(result, group)
	end
	return result
end

function BitZone:GetEntities(): { Types.Entity }
	local result = {}
	for _, group in pairs(State.Groups) do
		local count = #group._entities
		if count > 0 then
			local currentSize = #result
			table.move(group._entities, 1, count, currentSize + 1, result)
		end
	end
	return result
end

function BitZone:IsEntityValidType(entity: any): boolean
	if typeof(entity) == 'Instance' then
		if
			entity:IsA('BasePart')
			or entity:IsA('Attachment')
			or entity:IsA('Bone')
			or entity:IsA('Camera')
			or entity:IsA('Model')
		then
			return true
		end
	elseif typeof(entity) == 'table' then
		if entity.Position or entity.CFrame or entity.WorldPosition or entity.GetPivot then
			return true
		end
	end
	return false
end

function BitZone:IsEntityInAnyGroup(entity: Entity): boolean
	return State.EntityToGroup[entity] ~= nil
end

return BitZone
