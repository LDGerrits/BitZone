--!native
--!strict

local RunService = game:GetService('RunService')

local Geometry = require(script.Parent.Geometry)
local LinearBVH = require(script.Parent.LinearBVH)
local State = require(script.Parent.State)
local Config = require(script.Parent.Config)
local Types = require(script.Parent.Types)

local objects = State.objects
local zoneBoundGroups = State.zoneBoundGroups
local groupPriorityMap = State.groupPriorityMap
local itemCustomData = State.itemCustomData
local groupEnteredCallbacks = State.groupEnteredCallbacks
local groupTrackingItems = State.groupTrackingItems
local groupExitedCallbacks = State.groupExitedCallbacks
local zoneIndexToZoneObj = State.zoneIndexToZoneObj

local ctx_pos: Vector3
local ctx_collectionID: number
local ctx_cCount: number = 0
local ctx_highestWin: number
local ctx_candidatePriority: { [number]: number } = table.create(16)
local ctx_candidateIndex: { [number]: number } = table.create(16)
local ctx_candidateList: { [number]: number } = table.create(16)

local frameBudget = Config.Scheduler.FrameBudget

local STRAT_POS = Config.Strategy.POS
local STRAT_PRIM = Config.Strategy.PRIM
local STRAT_WORLD = Config.Strategy.WORLD
local STRAT_CFRAME = Config.Strategy.CFRAME

local function fireCallback(callbacks, item, zone, customData, safeMode)
	if not callbacks then
		return
	end

	if safeMode then
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
	if not Geometry.IsPointInShape(ctx_pos, objects[zoneId]) then
		return
	end

	local groups = zoneBoundGroups[zoneId]
	if not groups then
		return
	end

	local linkedGroups = State.collectionToGroups[ctx_collectionID]
	if not linkedGroups then
		return
	end

	local isRelevant = false
	for _, gUID in groups do
		-- Is this group even interested in this collection?
		if linkedGroups[gUID] then
			-- Do we already have a better candidate?
			if not ctx_candidatePriority[gUID] then
				isRelevant = true
				break
			end
		end
	end
	if not isRelevant then
		return
	end

	for _, gUID in groups do
		if linkedGroups[gUID] then
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
	local forceRefresh = State.isDirty
	State.isDirty = false

	-- Each collection is processed one-by-one
	for _, col in pairs(State.collections) do
		local list = col.Items
		local totalItems = #list
		if totalItems == 0 then
			continue
		end

		local settings = col.Settings
		local rate = settings.UpdateRate or 20
		local precSq = settings.PrecisionSq or 0.01
		local safeMode = settings.SafetyMode

		local workQuota = math.ceil(totalItems * rate * dt)
		if workQuota < 1 then
			workQuota = 1
		end
		if workQuota > totalItems then
			workQuota = totalItems
		end

		local processed = 0
		local idx = col.LastProcessedIndex
		if idx > totalItems then
			idx = 1
		end

		ctx_collectionID = col.ID

		while processed < workQuota do
			local item = list[idx]
			local d = col.ItemData[item] :: Types.ItemData?

			-- Race condition guard
			if not d then
				idx += 1
				if idx > totalItems then
					idx = 1
				end
				processed += 1
				continue
			end

			-- Strategy
			local pos
			local strategy = d.strategy
			if strategy == STRAT_POS then
				pos = (item :: BasePart).Position
			elseif strategy == STRAT_WORLD then
				pos = (item :: Attachment).WorldPosition
			elseif strategy == STRAT_CFRAME then
				pos = (item :: BasePart).CFrame.Position
			elseif strategy == STRAT_PRIM and (item :: Model).PrimaryPart then
				pos = (item.PrimaryPart :: BasePart).Position
			else
				pos = (item :: any):GetPivot().Position
			end

			-- Threshold
			local shouldCheck = forceRefresh or d.isDirty
			if not shouldCheck then
				local lp = d.lastPosition
				local dx, dy, dz = pos.X - lp.X, pos.Y - lp.Y, pos.Z - lp.Z
				if (dx * dx + dy * dy + dz * dz) >= precSq then
					shouldCheck = true
				end
			end

			if shouldCheck then
				d.lastPosition = pos
				d.isDirty = false

				ctx_pos = pos
				ctx_cCount = 0
				ctx_highestWin = -math.huge

				LinearBVH.QueryPoint(State.rootNode, pos, queryCallback)

				local current = d.activeGroupMemberships

				-- Exits
				for gUID, oldZoneIdx in pairs(current) do
					local newPri = ctx_candidatePriority[gUID]
					if not newPri or newPri < ctx_highestWin then
						current[gUID] = nil
						if groupTrackingItems[gUID] then
							groupTrackingItems[gUID][item] = nil
						end

						local cbs = groupExitedCallbacks[gUID]
						if cbs then
							local z = zoneIndexToZoneObj[oldZoneIdx]
							local cd = itemCustomData[item] and itemCustomData[item][gUID]
							fireCallback(cbs, item, z, cd, safeMode)
						end
					end
				end

				-- Entries
				for i = 1, ctx_cCount do
					local gUID = ctx_candidateList[i]
					local pri = ctx_candidatePriority[gUID]
					if pri >= ctx_highestWin and not current[gUID] then
						local newZoneIdx = ctx_candidateIndex[gUID]
						current[gUID] = newZoneIdx
						groupTrackingItems[gUID][item] = true
						local cbs = groupEnteredCallbacks[gUID]
						if cbs then
							local z = zoneIndexToZoneObj[newZoneIdx]
							local cd = itemCustomData[item] and itemCustomData[item][gUID]
							fireCallback(cbs, item, z, cd, safeMode)
						end
					end
					ctx_candidatePriority[gUID] = nil
					ctx_candidateIndex[gUID] = nil
					ctx_candidateList[i] = nil
				end
			end

			idx += 1
			if idx > totalItems then
				idx = 1
			end
			processed += 1

			-- Global budget check
			if processed % 42 == 0 and (os.clock() - start) > frameBudget then
				break
			end
		end

		col.LastProcessedIndex = idx

		if (os.clock() - start) > frameBudget then
			break
		end
	end

	debug.profileend()
end)

local Scheduler = {}

function Scheduler.SetFrameBudget(n: number)
	frameBudget = n
end

return Scheduler
