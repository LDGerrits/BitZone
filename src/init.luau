--!strict

local RunService = game:GetService('RunService')

local Group = require(script.Classes.Group)
local Geometry = require(script.Core.Geometry)
local LinearBVH = require(script.Core.LinearBVH)
local Types = require(script.Types)
local State = require(script.State)
local Zone = require(script.Classes.Zone)
local Observer = require(script.Classes.Observer)
local Scheduler = require(script.Core.Scheduler)

local staticShapes = State.staticShapes
local dynamicShapes = State.dynamicShapes
local zoneAttachedObservers = State.zoneAttachedObservers
local observerIdToObserverObj = State.observerIdToObserverObj

local debugConnection: RBXScriptConnection?
local debugFolder: Folder?
local debugVisuals = {} :: { [number]: BoxHandleAdornment }

local IS_CLIENT = RunService:IsClient()

export type QuickZone = Types.QuickZone
export type Zone = Types.Zone
export type Observer = Types.Observer
export type Group = Types.Group
export type Entity = Types.Entity

local QuickZone = {}

function QuickZone.Zone(
	cframe: CFrame,
	size: Vector3,
	shape: Types.ShapeType,
	associatedPart: BasePart?,
	isDynamic: boolean?
): Zone
	return Zone.new(cframe, size, shape, associatedPart, isDynamic)
end

function QuickZone.ZoneFromPart(part: BasePart, isDynamic: boolean?): Zone
	local shape: Types.ShapeType = 'Block'
	if (part :: any).Shape == Enum.PartType.Ball then
		shape = 'Ball'
	elseif (part :: any).Shape == Enum.PartType.Cylinder then
		shape = 'Cylinder'
	elseif part:IsA('WedgePart') then
		shape = 'Wedge'
	end
	return Zone.new(part.CFrame, part.Size, shape, part, isDynamic)
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

	if State.staticRootNode then
		LinearBVH.queryPoint(State.staticRootNode, position, function(zoneId)
			if Geometry.isPointInShape(position, staticShapes[zoneId]) then
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

function QuickZone:visualize(enable: boolean): QuickZone
	if debugConnection then
		debugConnection:Disconnect()
		debugConnection = nil
	end

	if debugFolder then
		debugFolder:Destroy()
		debugFolder = nil
	end
	table.clear(debugVisuals)

	if not enable then
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
			newBox.Transparency = 0.6
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
				local color = isActive and Color3.fromRGB(0, 255, 0) or Color3.fromRGB(255, 0, 0)
				updateVisual(id, shape, color)
			end
		end

		-- Draw dynamic zones
		for id, zone in dynamicShapes do
			local isActive = State.zoneAttachedObservers[id] ~= nil
			local color = isActive and Color3.fromRGB(0, 255, 100) or Color3.fromRGB(255, 0, 0)
			updateVisual(id, zone, color)
		end

		-- Remove destroyed zones
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
