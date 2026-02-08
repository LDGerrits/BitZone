--!native
--!strict

local RunService = game:GetService('RunService')

local Geometry = require(script.Parent.Geometry)
local LinearBVH = require(script.Parent.LinearBVH)
local Types = require(script.Parent.Types)
local State = require(script.Parent.State)
local Config = require(script.Parent.Config)

local itemList = State.itemList
local items = State.items
local objects = State.objects
local zoneBoundGroups = State.zoneBoundGroups
local groupPriorityMap = State.groupPriorityMap
local itemCustomData = State.itemCustomData
local groupEnteredCallbacks = State.groupEnteredCallbacks
local groupTrackingItems = State.groupTrackingItems
local groupExitedCallbacks = State.groupExitedCallbacks
local zoneIndexToZoneObj = State.zoneIndexToZoneObj

local lastProcessedIndex = 1
local ctx_pos: Vector3
local ctx_data: Types.ItemData
local ctx_cCount: number = 0
local ctx_highestWin: number
local ctx_candidatePriority: { [number]: number } = table.create(16)
local ctx_candidateIndex: { [number]: number } = table.create(16)
local ctx_candidateList: { [number]: number } = table.create(16)

local safetyMode = Config.Scheduler.SafetyMode
local frameBudget = Config.Scheduler.FrameBudget
local updateRate = Config.Scheduler.UpdateRate
local precision = Config.Scheduler.Precision
local precisionSq = precision * precision

local STRAT_POS = Config.Strategy.POS
local STRAT_PRIM = Config.Strategy.PRIM
local STRAT_WORLD = Config.Strategy.WORLD
local STRAT_CFRAME = Config.Strategy.CFRAME

local function fireCallback(callbacks, item, zone, customData)
	if not callbacks then
		return
	end

	if safetyMode then
		for _, cb in callbacks do
			task.spawn(cb, item, zone, customData)
		end
	else
		for _, cb in callbacks do
			cb(item, zone, customData)
		end
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

RunService.Heartbeat:Connect(function(dt: number)
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
	local forceRefresh = State.isDirty
	State.isDirty = false

	local totalItems = #itemList
	if totalItems == 0 then
		return
	end

	local workQuota = math.ceil(totalItems * updateRate * dt)
	if workQuota < 1 then
		workQuota = 1
	end
	if workQuota > totalItems then
		workQuota = totalItems
	end

	if lastProcessedIndex > totalItems then
		lastProcessedIndex = 1
	end

	while processed < workQuota do
		local item = itemList[lastProcessedIndex]
		local data = items[item]

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

		local shouldCheck = forceRefresh or data.isDirty
		if not shouldCheck then
			local lastPos = data.lastPosition
			local dx = pos.X - lastPos.X
			local dy = pos.Y - lastPos.Y
			local dz = pos.Z - lastPos.Z
			local d2 = (dx * dx) + (dy * dy) + (dz * dz)
			if d2 >= precisionSq then
				shouldCheck = true
			end
		end

		if shouldCheck then
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

				if pri >= ctx_highestWin and not current[gUID] then
					local newZoneIdx = ctx_candidateIndex[gUID]
					current[gUID] = newZoneIdx

					groupTrackingItems[gUID][item] = true

					local zone = zoneIndexToZoneObj[newZoneIdx]
					local cd = itemCustomData[item] and itemCustomData[item][gUID]
					fireCallback(groupEnteredCallbacks[gUID], item, zone, cd)
				end

				ctx_candidatePriority[gUID] = nil
				ctx_candidateIndex[gUID] = nil
				ctx_candidateList[i] = nil
			end
		end

		lastProcessedIndex += 1
		if lastProcessedIndex > totalItems then
			lastProcessedIndex = 1
		end

		processed += 1

		if processed % 32 == 0 and (os.clock() - start) > frameBudget then
			break
		end
	end
	debug.profileend()
end)

local Scheduler = {}

function Scheduler.SetUpdateRate(n: number)
	updateRate = n
end

function Scheduler.SetFrameBudget(n: number)
	frameBudget = n
end

function Scheduler.SetPrecision(n: number)
	precisionSq = n * n
end

function Scheduler.DisableSafetyMode()
	safetyMode = false
end

return Scheduler
