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
local Scheduler = require(script.Core.Scheduler)

local zones = State.zones
local zoneAttachedObservers = State.zoneAttachedObservers
local observerIdToObserverObj = State.observerIdToObserverObj

local IS_CLIENT = RunService:IsClient()
local DEBUG_FOLDER_NAME = 'QuickZone_Debug_Visuals'

export type QuickZone = Types.QuickZone
export type Zone = Types.Zone
export type Observer = Types.Observer
export type Group = Types.Group
export type Entity = Types.Entity

local QuickZone = {}

function QuickZone.Zone(cframe: CFrame, size: Vector3, shape: Types.ShapeType, associatedPart: BasePart?): Zone
	return Zone.new(cframe, size, shape, associatedPart)
end

function QuickZone.ZoneFromPart(part: BasePart): Zone
	local shape: Types.ShapeType = 'Block'
	if (part :: any).Shape == Enum.PartType.Ball then
		shape = 'Ball'
	elseif (part :: any).Shape == Enum.PartType.Cylinder then
		shape = 'Cylinder'
	end
	return Zone.new(part.CFrame, part.Size, shape, part)
end

function QuickZone.Observer(priority: number?): Observer
	return Observer.new(priority)
end

function QuickZone.Group(config: {
	updateRate: number?,
	precision: number?,
	safety: boolean?,
}?)
	return Group.new(config)
end

-- TODO
function QuickZone.PlayerGroup(config: {
	updateRate: number?,
	precision: number?,
	safety: boolean?,
}?): Group
	return
end

-- TODO
function QuickZone.LocalPlayerGroup(config: {
	updateRate: number?,
	precision: number?,
	safety: boolean?,
}?): Group
	assert(IS_CLIENT, '[QuickZone] TrackLocalPlayer can only be called on the Client.')

	return
end

function QuickZone:setFrameBudget(n: number): QuickZone
	Scheduler.setFrameBudget(n)
	return QuickZone
end

function QuickZone:getObserversAtPoint(position: Vector3): { Observer }
	local results = {}
	local foundIds = {}

	if State.rootNode then
		LinearBVH.queryPoint(State.rootNode, position, function(zoneId)
			if Geometry.isPointInShape(position, zones[zoneId]) then
				local observers = zoneAttachedObservers[zoneId]
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

function QuickZone:getGroupOfEntity(entity: Types.Entity): Types.Group?
	local groupId = State.entityToGroup[entity]
	if groupId then
		return State.groups[groupId]
	end
	return nil
end

function QuickZone:getZones(): { Types.Zone }
	local result = {}
	for _, zone in pairs(State.zoneIdToZoneObj) do
		table.insert(result, zone)
	end
	return result
end

function QuickZone:getObservers(): { Types.Observer }
	local result = {}
	for _, observer in pairs(State.observerIdToObserverObj) do
		table.insert(result, observer)
	end
	return result
end

function QuickZone:getGroups(): { Types.Group }
	local result = {}
	for _, group in pairs(State.groups) do
		table.insert(result, group)
	end
	return result
end

function QuickZone:getEntities(): { Types.Entity }
	local result = {}
	for _, group in pairs(State.groups) do
		local count = #group._entities
		if count > 0 then
			local currentSize = #result
			table.move(group._entities, 1, count, currentSize + 1, result)
		end
	end
	return result
end

function QuickZone:isEntityValidType(entity: any): boolean
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

function QuickZone:isEntityInAnyGroup(entity: Entity): boolean
	return State.entityToGroup[entity] ~= nil
end

function QuickZone:visualize(enabled: boolean): QuickZone
	local oldFolder = workspace:FindFirstChild(DEBUG_FOLDER_NAME)
	if oldFolder then
		oldFolder:Destroy()
	end

	if not enabled then
		return self
	end

	local folder = Instance.new('Folder')
	folder.Name = DEBUG_FOLDER_NAME
	folder.Parent = workspace

	for id, obj in State.zones do
		local box = Instance.new('BoxHandleAdornment')
		box.Size = obj.halfSize * 2
		box.CFrame = obj.cframe
		box.Adornee = workspace.Terrain
		box.Transparency = 0.6
		box.AlwaysOnTop = true
		box.ZIndex = 1

		local observers = State.zoneAttachedObservers[id]
		if observers and #observers > 0 then
			box.Color3 = Color3.fromRGB(0, 255, 0)
		else
			box.Color3 = Color3.fromRGB(255, 0, 0)
		end

		box.Parent = folder
	end

	return self
end

return QuickZone
