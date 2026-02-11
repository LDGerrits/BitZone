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
local Config = require(script.Config)
local Scheduler = require(script.Core.Scheduler)

local staticShapes = State.staticShapes
local dynamicShapes = State.dynamicShapes
local zoneAttachedObservers = State.zoneAttachedObservers
local observerIdToObserverObj = State.observerIdToObserverObj

local foundIdsCache = {}

local sharedPlayerGroup: Types.Group?
local sharedLocalPlayerGroup: Types.Group?
local bridgeRefreshPlayerGroup: ((Player) -> ())?

local debugConnection: RBXScriptConnection?
local debugFolder: Folder?
local debugVisuals = {} :: { [number]: BoxHandleAdornment }

local IS_CLIENT = RunService:IsClient()

export type QuickZone = Types.QuickZone
export type Zone = Types.Zone
export type Observer = Types.Observer
export type Group = Types.Group
export type Entity = Types.Entity

local function trackPlayer(group: Types.Group, player: Player, trackerStore: { [Player]: () -> () })
	if trackerStore[player] then
		return
	end

	local charConns: { RBXScriptConnection } = {}
	local currentHrp: BasePart? = nil

	local function cleanCharacter()
		if currentHrp then
			group:remove(currentHrp)
			currentHrp = nil
		end
		for _, c in charConns do
			c:Disconnect()
		end
		table.clear(charConns)
	end

	local function onCharAdded(char: Model)
		cleanCharacter()

		task.spawn(function()
			-- To prioritize LocalPlayerGroup, do early return if it is local player and LocalPlayerGroup exists
			if
				IS_CLIENT
				and group == sharedPlayerGroup
				and player == Players.LocalPlayer
				and sharedLocalPlayerGroup
			then
				return
			end

			local hrp = char:WaitForChild('HumanoidRootPart', 10)

			if not hrp or not player:IsDescendantOf(Players) then
				return
			end

			if player.Character ~= char then
				return
			end

			if hrp:IsA('BasePart') then
				currentHrp = hrp

				group:add(hrp, { Player = player }) -- Custom data is needed to trigger specific player events

				table.insert(
					charConns,
					hrp.AncestryChanged:Connect(function(_, parent)
						if not parent then
							cleanCharacter()
						end
					end)
				)
			end
		end)
	end

	local addedConn = player.CharacterAdded:Connect(onCharAdded)

	trackerStore[player] = function()
		addedConn:Disconnect()
		cleanCharacter()
	end

	if player.Character then
		onCharAdded(player.Character)
	end
end

local function untrackPlayer(player: Player, trackerStore: { [Player]: () -> () })
	local cleanup = trackerStore[player]
	if cleanup then
		cleanup()
		trackerStore[player] = nil
	end
end

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
}?): Group
	return Group.new(config)
end

function QuickZone.PlayerGroup(config: {
	updateRate: number?,
	precision: number?,
	safety: boolean?,
}?): Group
	if sharedPlayerGroup then
		if config then
			sharedPlayerGroup:setConfig(config)
		end
		return sharedPlayerGroup
	end

	local group = Group.new(config)
	sharedPlayerGroup = group

	local trackerStore = {} :: { [Player]: () -> () }
	local mainConnections = {} :: { RBXScriptConnection }

	bridgeRefreshPlayerGroup = function(player: Player)
		untrackPlayer(player, trackerStore)
		trackPlayer(group, player, trackerStore)
	end

	table.insert(
		mainConnections,
		Players.PlayerAdded:Connect(function(player)
			trackPlayer(group, player, trackerStore)
		end)
	)

	table.insert(
		mainConnections,
		Players.PlayerRemoving:Connect(function(player)
			untrackPlayer(player, trackerStore)
		end)
	)

	for _, player in Players:GetPlayers() do
		trackPlayer(group, player, trackerStore)
	end

	local originalDestroyHook = group.destroy
	group.destroy = function(self)
		for _, conn in mainConnections do
			conn:Disconnect()
		end
		for _, cleanup in trackerStore do
			cleanup()
		end

		table.clear(mainConnections)
		table.clear(trackerStore)

		bridgeRefreshPlayerGroup = nil
		sharedPlayerGroup = nil

		originalDestroyHook(self)
	end

	return group
end

function QuickZone.LocalPlayerGroup(config: {
	updateRate: number?,
	precision: number?,
	safety: boolean?,
}?): Group
	assert(IS_CLIENT, '[QuickZone] LocalPlayerGroup can only be called on the Client.')

	if sharedLocalPlayerGroup then
		if config then
			sharedLocalPlayerGroup:setConfig(config)
		end
		return sharedLocalPlayerGroup
	end

	local group = Group.new(config)
	sharedLocalPlayerGroup = group

	local lp = Players.LocalPlayer
	local trackers = {}

	trackPlayer(group, lp, trackers)

	local originalDestroyHook = group.destroy
	group.destroy = function(self)
		untrackPlayer(lp, trackers)
		sharedLocalPlayerGroup = nil

		-- The player should immediately be handed over to PlayerGroup
		if bridgeRefreshPlayerGroup then
			bridgeRefreshPlayerGroup(Players.LocalPlayer)
		end

		originalDestroyHook(self)
	end

	return group
end

function QuickZone:setFrameBudget(n: number): QuickZone
	Scheduler.setFrameBudget(n)
	return QuickZone
end

function QuickZone:getObserversAtPoint(position: Vector3): { Observer }
	table.clear(foundIdsCache)
	local results = {}

	local function checkZone(zoneId: number, shapeList: { [number]: Types.BoundingVolume })
		if not Geometry.isPointInShape(position, shapeList[zoneId]) then
			return
		end

		local observers = zoneAttachedObservers[zoneId]
		if not observers then
			return
		end

		for _, id in observers do
			if foundIdsCache[id] then
				continue
			end
			foundIdsCache[id] = true

			local observer = observerIdToObserverObj[id]
			if observer then
				table.insert(results, observer)
			end
		end
	end

	if State.dynamicRootNode then
		LinearBVH.queryPoint(State.dynamicRootNode, position, function(zoneId)
			checkZone(zoneId, dynamicShapes)
		end)
	end

	if State.staticRootNode then
		LinearBVH.queryPoint(State.staticRootNode, position, function(zoneId)
			checkZone(zoneId, staticShapes)
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
	for _, zone in State.zoneIdToZoneObj do
		table.insert(result, zone)
	end
	return result
end

function QuickZone:getObservers(): { Types.Observer }
	local result = {}
	for _, observer in State.observerIdToObserverObj do
		table.insert(result, observer)
	end
	return result
end

function QuickZone:getGroups(): { Types.Group }
	local result = {}
	for _, group in State.groups do
		table.insert(result, group)
	end
	return result
end

function QuickZone:getEntities(): { Types.Entity }
	local result = {}
	for _, group in State.groups do
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
		return entity:IsA('BasePart')
			or entity:IsA('Attachment')
			or entity:IsA('Bone')
			or entity:IsA('Camera')
			or entity:IsA('Model')
	elseif typeof(entity) == 'table' then
		return entity.Position or entity.CFrame or entity.WorldPosition or entity.GetPivot
	end
	return false
end

function QuickZone:isEntityInAnyGroup(entity: Entity): boolean
	return State.entityToGroup[entity] ~= nil
end

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

	local function updateVisual(id: number, shape: Types.BoundingVolume, color: Color3)
		local box = debugVisuals[id]

		if not box then
			local newBox = Instance.new('BoxHandleAdornment')
			newBox.Name = 'Zone_' .. id
			newBox.Adornee = workspace.Terrain
			newBox.Transparency = Config.Debug.transparency
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
				local color = isActive and Config.Debug.staticActive or Config.Debug.staticInactive
				updateVisual(id, shape, color)
			end
		end

		-- Draw dynamic zones
		for id, zone in dynamicShapes do
			local isActive = State.zoneAttachedObservers[id] ~= nil
			local color = isActive and Config.Debug.dynamicActive or Config.Debug.dynamicInactive
			updateVisual(id, zone, color)
		end

		-- Destroy removed zones
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
