--!strict

local Players = game:GetService('Players')
local RunService = game:GetService('RunService')

local Geometry = require(script.Parent.Geometry)
local LinearBVH = require(script.Parent.LinearBVH)
local State = require(script.Parent.State)
local Types = require(script.Parent.Types)

local IS_CLIENT = RunService:IsClient()

local Group = {}
Group.__index = Group

function Group.new(priority: number?): Types.Group
	local group = (
		setmetatable({
			UID = State.nextGroupId,
			_mainConnections = {},
			_playerTrackers = {},
		}, Group) :: any
	) :: Types.Group

	State.groupPriorityMap[group.UID] = priority or 0
	State.groupEnteredCallbacks[group.UID] = {}
	State.groupExitedCallbacks[group.UID] = {}
	State.groupTrackingItems[group.UID] = {}
	State.groupUIDToGroupObj[group.UID] = group

	State.nextGroupId += 1
	return group
end

function Group:SetPriority(p: number): Types.Group
	State.groupPriorityMap[self.UID] = p
	State.isDirty = true
	return self
end

function Group:TrackCollection(collection: Types.Collection): Types.Group
	local colID = collection.ID
	if not State.collectionToGroups[colID] then
		State.collectionToGroups[colID] = {}
	end
	State.collectionToGroups[colID][self.UID] = true
	return self
end

function Group:UntrackCollection(collection: Types.Collection): Types.Group
	local colID = collection.ID
	if State.collectionToGroups[colID] then
		State.collectionToGroups[colID][self.UID] = nil
	end

	-- Force evict items from this collection
	local safetyMode = collection.Settings.SafetyMode
	for _, item in collection.Items do
		local data = collection.ItemData[item]
		local oldZoneIdx = data and data.activeGroupMemberships[self.UID]
		if oldZoneIdx then
			data.activeGroupMemberships[self.UID] = nil
			State.groupTrackingItems[self.UID][item] = nil

			local z = State.zoneIndexToZoneObj[oldZoneIdx]
			local cbs = State.groupExitedCallbacks[self.UID]
			if cbs then
				local cd = State.itemCustomData[item] and State.itemCustomData[item][self.UID]
				for _, fn in cbs do
					if safetyMode then
						task.spawn(fn, item, z, cd)
					else
						fn(item, z, cd)
					end
				end
			end
		end
	end

	return self
end

function Group:IsPlayerInside(player: Player): boolean
	local character = player.Character
	if not character then
		return false
	end

	local hrp = character:FindFirstChild('HumanoidRootPart')
	if not hrp then
		return false
	end

	return self:IsItemInside(hrp)
end

function Group:IsLocalPlayerInside(): boolean
	if not IS_CLIENT then
		error('[BitZone] IsLocalPlayerInside can only be called on the Client.', 2)
	end

	return self:IsPlayerInside(Players.LocalPlayer)
end

function Group:IsItemInside(item: Types.Item): boolean
	local colID = State.itemToCollection[item]
	if not colID then
		return false
	end

	local collection = State.collections[colID]
	local data = collection.ItemData[item]
	if not data then
		return false
	end

	return data.activeGroupMemberships[self.UID] ~= nil
end

function Group:IsPointInside(position: Vector3): boolean
	if not State.rootNode then
		return false
	end

	local isInside = false
	LinearBVH.QueryPoint(State.rootNode, position, function(zoneId)
		if isInside then
			return
		end
		local groups = State.zoneBoundGroups[zoneId]
		if groups and table.find(groups, self.UID) then
			if Geometry.IsPointInShape(position, State.objects[zoneId]) then
				isInside = true
			end
		end
	end)

	return isInside
end

function Group:GetItemsInside(): { Types.Item }
	local items = State.groupTrackingItems[self.UID]
	if not items then
		return {}
	end
	local results = {}
	for item, _ in pairs(items) do
		table.insert(results, item)
	end
	return results
end

function Group:GetItems(): { Types.Item }
	local results = {}
	for colID, groups in pairs(State.collectionToGroups) do
		if groups[self.UID] then
			local collection = State.collections[colID]
			for _, item in ipairs(collection.Items) do
				table.insert(results, item)
			end
		end
	end
	return results
end

function Group:GetZones(): { Types.Zone }
	local results = {}
	for zoneIdx, boundList in pairs(State.zoneBoundGroups) do
		if table.find(boundList, self.UID) then
			local zone = State.zoneIndexToZoneObj[zoneIdx]
			if zone then
				table.insert(results, zone)
			end
		end
	end
	return results
end

-- TODO
function Group:GetCollections(): { Types.Collection }
	return {}
end

function Group:OnEntered(callback): () -> ()
	table.insert(State.groupEnteredCallbacks[self.UID], callback)
	return function()
		local i = table.find(State.groupEnteredCallbacks[self.UID], callback)
		if i then
			table.remove(State.groupEnteredCallbacks[self.UID], i)
		end
	end
end

function Group:OnExited(callback): () -> ()
	table.insert(State.groupExitedCallbacks[self.UID], callback)
	return function()
		local i = table.find(State.groupExitedCallbacks[self.UID], callback)
		if i then
			table.remove(State.groupExitedCallbacks[self.UID], i)
		end
	end
end

function Group:OnPlayerEntered(callback: (Player, Types.Zone) -> ()): () -> ()
	return self:OnEntered(function(_item, zone, data: { Player: Player }?)
		if data and data.Player then
			callback(data.Player, zone)
		end
	end)
end

function Group:OnPlayerExited(callback: (Player, Types.Zone) -> ()): () -> ()
	return self:OnExited(function(_item, zone, data: { Player: Player }?)
		if data and data.Player then
			callback(data.Player, zone)
		end
	end)
end

function Group:OnLocalPlayerEntered(callback: (Types.Zone) -> ()): () -> ()
	assert(IS_CLIENT, '[BitZone] OnLocalPlayerEntered can only be called on the Client.')
	return self:OnEntered(function(_item, zone, data: { Player: Player }?)
		if data and data.Player == Players.LocalPlayer then
			callback(zone)
		end
	end)
end

function Group:OnLocalPlayerExited(callback: (Types.Zone) -> ()): () -> ()
	assert(IS_CLIENT, '[BitZone] OnLocalPlayerExited can only be called on the Client.')
	return self:OnExited(function(_item, zone, data: { Player: Player }?)
		if data and data.Player == Players.LocalPlayer then
			callback(zone)
		end
	end)
end

function Group:Destroy(): ()
	local uid = self.UID
	for _, groups in pairs(State.collectionToGroups) do
		groups[uid] = nil
	end

	for _, boundList in pairs(State.zoneBoundGroups) do
		local idx = table.find(boundList, uid)
		while idx do
			table.remove(boundList, idx)
			idx = table.find(boundList, uid)
		end
	end

	State.groupPriorityMap[uid] = nil
	State.groupEnteredCallbacks[uid] = nil
	State.groupExitedCallbacks[uid] = nil
	State.groupTrackingItems[uid] = nil
	State.groupUIDToGroupObj[uid] = nil
	State.isDirty = true
	setmetatable(self :: any, nil)
end

return Group
