--!strict
local Players = game:GetService('Players')
local RunService = game:GetService('RunService')

local Collection = require(script.Collection)
local Geometry = require(script.Geometry)
local LinearBVH = require(script.LinearBVH)
local Types = require(script.Types)
local State = require(script.State)
local Zone = require(script.Zone)
local Group = require(script.Group)
local Scheduler = require(script.Scheduler)

local objects = State.objects
local zoneBoundGroups = State.zoneBoundGroups
local groupUIDToGroupObj = State.groupUIDToGroupObj

local IS_CLIENT = RunService:IsClient()

export type BitZone = Types.BitZone
export type Zone = Types.Zone
export type Group = Types.Group
export type Collection = Types.Collection
export type Item = Types.Item
export type CollectionConfig = Types.CollectionConfig

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

function BitZone.newGroup(priority: number?): Group
	return Group.new(priority)
end

function BitZone.newCollection(config: CollectionConfig?)
	return Collection.new(config)
end

-- TODO
function BitZone.playersCollection(config: CollectionConfig?): Collection
	return
end

-- TODO
function BitZone.localPlayerCollection(config: CollectionConfig?): Collection
	assert(IS_CLIENT, '[BitZone] TrackLocalPlayer can only be called on the Client.')

	return
end

function BitZone:SetFrameBudget(n: number): BitZone
	assert(n > 0, '[BitZone] FrameBudget must be greater than 0')

	Scheduler.SetFrameBudget(n)
	return BitZone
end

function BitZone:GetGroupsAtPoint(position: Vector3): { Group }
	local results = {}
	local foundUIDs = {}

	if State.rootNode then
		LinearBVH.QueryPoint(State.rootNode, position, function(zoneId)
			if Geometry.IsPointInShape(position, objects[zoneId]) then
				local groups = zoneBoundGroups[zoneId]
				if groups then
					for _, uid in groups do
						if not foundUIDs[uid] then
							foundUIDs[uid] = true
							local group = groupUIDToGroupObj[uid]
							if group then
								table.insert(results, group)
							end
						end
					end
				end
			end
		end)
	end
	return results
end

function BitZone:GetCollectionOfItem(item: Item): Collection?
	return State.itemToCollection[item]
end

-- TODO
function BitZone:GetZones(): { Zone }
	return {}
end

-- TODO
function BitZone:GetGroups(): { Group }
	return {}
end

-- TODO
function BitZone:GetCollections(): { Collection }
	return {}
end

-- TODO
function BitZone:GetItems(): { Item }
	return {}
end

function BitZone:IsItemValidType(item: any): boolean
	if typeof(item) == 'Instance' then
		if
			item:IsA('BasePart')
			or item:IsA('Attachment')
			or item:IsA('Bone')
			or item:IsA('Camera')
			or item:IsA('Model')
		then
			return true
		end
	elseif typeof(item) == 'table' then
		if item.Position or item.CFrame or item.WorldPosition or item.GetPivot then
			return true
		end
	end
	return false
end

function BitZone:IsItemInAnyCollection(item: Item): boolean
	return State.itemToCollection[item] ~= nil
end

return BitZone
