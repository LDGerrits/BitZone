--!strict

local Geometry = require(script.Geometry)
local LinearBVH = require(script.LinearBVH)
local Types = require(script.Types)
local State = require(script.State)
local Zone = require(script.Zone)
local Group = require(script.Group)
local Scheduler = require(script.Scheduler)

local items = State.items
local objects = State.objects
local zoneBoundGroups = State.zoneBoundGroups
local groupUIDToGroupObj = State.groupUIDToGroupObj

export type BitZone = Types.BitZone
export type Zone = Types.Zone
export type Group = Types.Group
export type Item = Types.Item

local BitZone = {}

function BitZone:SetFrameBudget(n: number): BitZone
	assert(n > 0, '[BitZone] FrameBudget must be greater than 0')

	Scheduler.SetFrameBudget(n)
	return BitZone
end

function BitZone:SetUpdateRate(n: number): BitZone
	assert(n > 0, '[BitZone] UpdateRate must be greater than 0')

	Scheduler.SetFrameBudget(n)
	return BitZone
end

function BitZone:SetPrecision(n: number): BitZone
	assert(n >= 0, '[BitZone] Precision must be non-negative')

	Scheduler.SetPrecision(n)
	return BitZone
end

function BitZone:DisableSafetyMode(): BitZone
	Scheduler.DisableSafetyMode()
	return BitZone
end

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

function BitZone:CanItemBeTracked(item: any): boolean
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

function BitZone:IsItemTracked(item: Item): boolean
	local data = State.items[item]
	return data ~= nil
end

function BitZone:GetGroupsForItem(item: Item): { Group }
	local data = items[item]
	if not data then
		return {}
	end

	local results = {}
	for gUID, _ in pairs(data.memberOfGroups) do
		local group = groupUIDToGroupObj[gUID]
		if group then
			table.insert(results, group)
		end
	end
	return results
end

function BitZone:GetGroupsAtItem(item: Item): { Group }
	local data = items[item]
	if not data then
		return {}
	end

	local results = {}
	for gUID, _ in pairs(data.activeGroupMemberships) do
		local group = groupUIDToGroupObj[gUID]
		if group then
			table.insert(results, group)
		end
	end
	return results
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

return BitZone
