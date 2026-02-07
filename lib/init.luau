--!native
--!strict

local RunService = game:GetService('RunService')

local Geometry = require(script.Geometry)
local LinearBVH = require(script.LinearBVH)
local Types = require(script.Types)
local State = require(script.State)
local Zone = require(script.Zone)
local Group = require(script.Group)
local Strategy = require(script.Strategy)

local items = State.items
local objects = State.objects
local zoneBoundGroups = State.zoneBoundGroups
local groupPriorityMap = State.groupPriorityMap
local itemCustomData = State.itemCustomData
local groupEnteredCallbacks = State.groupEnteredCallbacks
local groupTrackingItems = State.groupTrackingItems
local groupExitedCallbacks = State.groupExitedCallbacks
local zoneIndexToZoneObj = State.zoneIndexToZoneObj

local ctx_pos: Vector3
local ctx_data: Types.ItemData
local ctx_cCount: number = 0
local ctx_highestWin: number
local ctx_candidatePriority: { [number]: number } = table.create(16)
local ctx_candidateIndex: { [number]: number } = table.create(16)
local ctx_candidateList: { [number]: number } = table.create(16)

local MOVE_THRESHOLD = 0.1
local MOVE_THRESHOLD_SQ = MOVE_THRESHOLD * MOVE_THRESHOLD

local STRAT_POS = Strategy.POS
local STRAT_PRIM = Strategy.PRIM
local STRAT_WORLD = Strategy.WORLD
local STRAT_CFRAME = Strategy.CFRAME

local function fireCallback(callbacks, item, zone, customData)
	if not callbacks then
		return
	end

	for _, cb in callbacks do
		task.spawn(cb, item, zone, customData)
	end
end

local function queryCallback(zoneId: number)
	local groups = zoneBoundGroups[zoneId]
	if not groups then
		return
	end

	local memberOfGroups = ctx_data.memberOfGroups

	local isMemberOfAny = false
	for _, gUID in groups do
		if memberOfGroups[gUID] then
			if not ctx_candidatePriority[gUID] then
				isMemberOfAny = true
				break
			end
		end
	end

	if not isMemberOfAny then
		return
	end

	if not Geometry.IsPointInShape(ctx_pos, objects[zoneId]) then
		return
	end

	for _, gUID in groups do
		if memberOfGroups[gUID] then
			local pri = groupPriorityMap[gUID] or 0

			ctx_cCount += 1
			ctx_candidateList[ctx_cCount] = gUID
			ctx_candidateIndex[gUID] = zoneId
			ctx_candidatePriority[gUID] = pri

			if pri > ctx_highestWin then
				ctx_highestWin = pri
			end
		end
	end
end

RunService.Heartbeat:Connect(function()
	if State.pendingRebuild then
		debug.profilebegin('QuickBounds_Build')
		State.rootNode = LinearBVH.Build(objects)
		State.pendingRebuild = false
		debug.profileend()
		State.isDirty = true
	end

	if not State.rootNode then
		return
	end

	debug.profilebegin('QuickBounds_Step')
	local start = os.clock()
	local processed = 0
	local frameBudget = State.frameBudget
	local forceRefresh = State.isDirty
	State.isDirty = false

	for item, data in items do
		local pos
		local strategy = data.strategy
		if strategy == STRAT_POS then
			pos = (item :: any).Position
		elseif strategy == STRAT_WORLD then
			pos = (item :: any).WorldPosition
		elseif strategy == STRAT_PRIM then
			pos = (item :: any).PrimaryPart.Position
		elseif strategy == STRAT_CFRAME then
			pos = (item :: any).CFrame.Position
		else
			pos = (item :: any):GetPivot().Position
		end

		if not forceRefresh and not data.isDirty then
			local lastPos = data.lastPosition
			local dx = pos.X - lastPos.X
			local dy = pos.Y - lastPos.Y
			local dz = pos.Z - lastPos.Z
			local d2 = (dx * dx) + (dy * dy) + (dz * dz)
			if d2 < MOVE_THRESHOLD_SQ then
				continue
			end
		end

		data.lastPosition = pos
		data.isDirty = false

		-- Query spatial map
		ctx_pos = pos
		ctx_data = data
		ctx_cCount = 0
		ctx_highestWin = -math.huge

		LinearBVH.QueryPoint(State.rootNode, pos, queryCallback)

		local current = data.activeGroupMemberships

		-- Check exits
		for gUID, oldZoneIdx in current do
			local newPri = ctx_candidatePriority[gUID]
			if not newPri or newPri < ctx_highestWin then
				current[gUID] = nil

				if groupTrackingItems[gUID] then
					groupTrackingItems[gUID][item] = nil
				end

				local zone = zoneIndexToZoneObj[oldZoneIdx]
				local cd = itemCustomData[item] and itemCustomData[item][gUID]
				fireCallback(groupExitedCallbacks[gUID], item, zone, cd)
			end
		end

		-- Check entries
		for i = 1, ctx_cCount do
			local gUID = ctx_candidateList[i]
			local pri = ctx_candidatePriority[gUID]

			if pri >= ctx_highestWin then
				if not current[gUID] then
					local newZoneIdx = ctx_candidateIndex[gUID]
					current[gUID] = newZoneIdx

					groupTrackingItems[gUID][item] = true

					local zone = zoneIndexToZoneObj[newZoneIdx]
					local cd = itemCustomData[item] and itemCustomData[item][gUID]
					fireCallback(groupEnteredCallbacks[gUID], item, zone, cd)
				end
			end

			ctx_candidatePriority[gUID] = nil
			ctx_candidateIndex[gUID] = nil
			ctx_candidateList[i] = nil
		end

		processed += 1
		if processed % 32 == 0 and (os.clock() - start) > frameBudget then
			break
		end
	end
	debug.profileend()
end)

export type Group = Types.Group
export type Zone = Types.Zone
export type Item = Types.Item

return {
	newZone = Zone.new,
	newGroup = Group.new,

	newZoneFromPart = function(part: BasePart): Types.Zone
		local shape: Types.ShapeType = 'Block'
		if (part :: any).Shape == Enum.PartType.Ball then
			shape = 'Ball'
		elseif (part :: any).Shape == Enum.PartType.Cylinder then
			shape = 'Cylinder'
		end
		return Zone.new(part.CFrame, part.Size, shape, part)
	end,

	CanItemBeTracked = function(item: any): boolean
		if typeof(item) == 'Instance' then
			if item:IsA('BasePart') then
				return true
			elseif item:IsA('Attachment') or item:IsA('Bone') then
				return true
			elseif item:IsA('Camera') then
				return true
			elseif item:IsA('Model') then
				return true
			end
		elseif typeof(item) == 'table' then
			if item.Position then
				return true
			elseif item.CFrame then
				return true
			elseif item.WorldPosition then
				return true
			elseif item.GetPivot then
				return true
			end
		end

		return false
	end,

	IsItemTracked = Group.IsItemTracked,

	GetGroupsForItem = function(item: Types.Item): { Types.Group }
		local data = State.items[item]
		if not data then
			return {}
		end
		local results = {}
		for gUID, _ in data.memberOfGroups do
			local group = State.groupUIDToGroupObj[gUID]
			if group then
				table.insert(results, group)
			end
		end
		return results
	end,

	GetGroupsAtItem = function(item: Types.Item): { Types.Group }
		local data = State.items[item]
		if not data then
			return {}
		end
		local results = {}
		for gUID, _ in data.activeGroupMemberships do
			local group = State.groupUIDToGroupObj[gUID]
			if group then
				table.insert(results, group)
			end
		end
		return results
	end,

	GetGroupsAtPoint = function(position: Vector3): { Types.Group }
		local results = {}
		local foundUIDs = {}
		if State.rootNode then
			LinearBVH.QueryPoint(State.rootNode, position, function(zoneId)
				if Geometry.IsPointInShape(position, objects[zoneId]) then
					local groups = State.zoneBoundGroups[zoneId]
					if groups then
						for _, uid in groups do
							if not foundUIDs[uid] then
								foundUIDs[uid] = true
								local group = State.groupUIDToGroupObj[uid]
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
	end,

	SetFrameBudget = function(n: number)
		State.frameBudget = n
	end,
}
