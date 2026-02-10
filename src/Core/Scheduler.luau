--!native
--!strict

local RunService = game:GetService('RunService')

local Geometry = require(script.Parent.Geometry)
local LinearBVH = require(script.Parent.LinearBVH)
local State = require(script.Parent.Parent.State)
local Config = require(script.Parent.Parent.Config)
local Types = require(script.Parent.Parent.Types)

local objects = State.objects
local zoneAttachedObservers = State.zoneAttachedObservers
local observerPriorityMap = State.ObserverPriorityMap
local entityCustomData = State.entityCustomData
local observerEnteredCallbacks = State.observerEnteredCallbacks
local observerTrackingEntities = State.observerTrackingEntities
local observerExitedCallbacks = State.observerExitedCallbacks
local zoneIdToZoneObj = State.zoneIdToZoneObj

local ctx_pos: Vector3
local ctx_groupId: number
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

local function fireCallback(callbacks, entity, zone, customData, safeMode)
	if not callbacks then
		return
	end

	if safeMode then
		for _, cb in callbacks do
			task.spawn(cb, entity, zone, customData)
		end
	else
		for _, cb in callbacks do
			cb(entity, zone, customData)
		end
	end
end

local function queryCallback(zoneId: number)
	if not Geometry.isPointInShape(ctx_pos, objects[zoneId]) then
		return
	end

	local observers = zoneAttachedObservers[zoneId]
	if not observers then
		return
	end

	local linkedObservers = State.groupToObservers[ctx_groupId]
	if not linkedObservers then
		return
	end

	local isRelevant = false
	for _, gId in observers do
		if linkedObservers[gId] then
			if not ctx_candidatePriority[gId] then
				isRelevant = true
				break
			end
		end
	end
	if not isRelevant then
		return
	end

	for _, gId in observers do
		if linkedObservers[gId] then
			local pri = observerPriorityMap[gId] or 0
			ctx_cCount += 1
			ctx_candidateList[ctx_cCount] = gId
			ctx_candidateIndex[gId] = zoneId
			ctx_candidatePriority[gId] = pri
			if pri > ctx_highestWin then
				ctx_highestWin = pri
			end
		end
	end
end

RunService.Heartbeat:Connect(function(dt: number)
	if State.pendingRebuild then
		debug.profilebegin('QuickZone_Build')
		State.rootNode = LinearBVH.build(objects)
		State.pendingRebuild = false
		debug.profileend()
		State.isDirty = true
	end

	if not State.rootNode then
		return
	end

	debug.profilebegin('QuickZone_Step')
	local start = os.clock()
	local forceRefresh = State.isDirty
	State.isDirty = false

	-- Each group is processed one-by-one
	for _, group in pairs(State.groups) do
		local list = group._entities
		local totalEntities = #list
		if totalEntities == 0 then
			continue
		end

		local config = group._config
		local rate = config.updateRate or 20
		local precSq = config.PrecisionSq or 0.01
		local safeMode = config.safety

		local workQuota = math.ceil(totalEntities * rate * dt)
		if workQuota < 1 then
			workQuota = 1
		end
		if workQuota > totalEntities then
			workQuota = totalEntities
		end

		local processed = 0
		local idx = group._lastProcessedIndex
		if idx > totalEntities then
			idx = 1
		end

		ctx_groupId = group.id

		while processed < workQuota do
			local entity = list[idx]
			local d = group._entityData[entity] :: Types.EntityData?

			-- Race condition guard
			if not d then
				idx += 1
				if idx > totalEntities then
					idx = 1
				end
				processed += 1
				continue
			end

			-- Strategy
			local pos
			local strategy = d.strategy
			if strategy == STRAT_POS then
				pos = (entity :: BasePart).Position
			elseif strategy == STRAT_WORLD then
				pos = (entity :: Attachment).WorldPosition
			elseif strategy == STRAT_CFRAME then
				pos = (entity :: BasePart).CFrame.Position
			elseif strategy == STRAT_PRIM and (entity :: Model).PrimaryPart then
				pos = ((entity :: Model).PrimaryPart :: BasePart).Position
			else
				pos = (entity :: any):GetPivot().Position
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

				LinearBVH.queryPoint(State.rootNode, pos, queryCallback)

				local current = d.activeObserverMemberships

				-- Exits
				for gId, oldZoneId in pairs(current) do
					local newPri = ctx_candidatePriority[gId]
					if not newPri or newPri < ctx_highestWin then
						current[gId] = nil
						if observerTrackingEntities[gId] then
							observerTrackingEntities[gId][entity] = nil
						end

						local cbs = observerExitedCallbacks[gId]
						if cbs then
							local z = zoneIdToZoneObj[oldZoneId]
							local cd = entityCustomData[entity] and entityCustomData[entity][gId]
							fireCallback(cbs, entity, z, cd, safeMode)
						end
					end
				end

				-- Entries
				for i = 1, ctx_cCount do
					local gId = ctx_candidateList[i]
					local pri = ctx_candidatePriority[gId]
					if pri >= ctx_highestWin and not current[gId] then
						local ZoneIdx = ctx_candidateIndex[gId]
						current[gId] = ZoneIdx
						observerTrackingEntities[gId][entity] = true
						local cbs = observerEnteredCallbacks[gId]
						if cbs then
							local z = zoneIdToZoneObj[ZoneIdx]
							local cd = entityCustomData[entity] and entityCustomData[entity][gId]
							fireCallback(cbs, entity, z, cd, safeMode)
						end
					end
					ctx_candidatePriority[gId] = nil
					ctx_candidateIndex[gId] = nil
					ctx_candidateList[i] = nil
				end
			end

			idx += 1
			if idx > totalEntities then
				idx = 1
			end
			processed += 1

			-- Global budget check
			if processed % 42 == 0 and (os.clock() - start) > frameBudget then
				break
			end
		end

		group._lastProcessedIndex = idx

		if (os.clock() - start) > frameBudget then
			break
		end
	end

	debug.profileend()
end)

local Scheduler = {}

function Scheduler.setFrameBudget(n: number)
	frameBudget = n
end

return Scheduler
