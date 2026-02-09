--!strict
local State = require(script.Parent.State)
local Types = require(script.Parent.Types)
local Config = require(script.Parent.Config)

local STRAT_POS = Config.Strategy.POS
local STRAT_PRIM = Config.Strategy.PRIM
local STRAT_WORLD = Config.Strategy.WORLD
local STRAT_CFRAME = Config.Strategy.CFRAME
local STRAT_PIVOT = Config.Strategy.PIVOT

local Collection = {}
Collection.__index = Collection

function Collection.new(config: Types.CollectionConfig?): Types.Collection
	local id = State.nextCollectionId
	State.nextCollectionId += 1

	-- TODO need to add these props to Types
	local self = setmetatable({
		ID = id,
		Items = {}, -- Dense Array [1]=Item
		ItemIndices = {}, -- Lookup [Item]=1
		ItemData = {}, -- Data [Item]={lastPos...}
		Settings = {
			UpdateRate = config and config.UpdateRate or Config.Scheduler.UpdateRate,
			PrecisionSq = (config and config.Precision or Config.Scheduler.Precision) ^ 2,
			SafetyMode = config and config.SafetyMode or Config.Scheduler.SafetyMode,
		},
		LastProcessedIndex = 1,
	}, Collection)

	State.collections[id] = self
	State.collectionToGroups[id] = {}

	return (self :: any) :: Types.Collection
end

function Collection:SetUpdateRate(hz: number): Types.Collection
	assert(hz > 0, '[BitZone] UpdateRate must be greater than 0')

	self.Settings.UpdateRate = hz
	return self
end

function Collection:SetPrecision(n: number): Types.Collection
	assert(n >= 0, '[BitZone] Precision must be non-negative')

	self.Settings.PrecisionSq = n
	return self
end

function Collection:SetSafetyMode(enabled: boolean): Types.Collection
	self.Settings.SafetyMode = enabled
	return self
end

function Collection:Add(item: Types.Item, customData: any?): Types.Collection
	local oldColID = State.itemToCollection[item]
	if oldColID then
		if oldColID == self.ID then
			return self
		end
		local oldCol = State.collections[oldColID]
		if oldCol then
			oldCol:Remove(item)
		end
	end

	local strat
	if typeof(item) == 'Instance' then
		if item:IsA('BasePart') then
			strat = STRAT_POS
		elseif item:IsA('Attachment') or item:IsA('Bone') then
			strat = STRAT_WORLD
		elseif item:IsA('Camera') then
			strat = STRAT_CFRAME
		elseif item:IsA('Model') then
			strat = item.PrimaryPart and STRAT_PRIM or STRAT_PIVOT
		end
	elseif typeof(item) == 'table' then
		if item.Position then
			strat = STRAT_POS
		elseif item.CFrame then
			strat = STRAT_CFRAME
		elseif item.WorldPosition then
			strat = STRAT_WORLD
		elseif item.GetPivot then
			strat = STRAT_PIVOT
		end
	end

	if not strat then
		error(
			string.format(
				'[BitZone] TrackItem Failed: The provided item (%s) is not a supported type. '
					.. 'Ensure it is a BasePart, Model, Attachment, Bone, Camera, or a table with a Position/CFrame.',
				tostring(item)
			),
			2
		)
	end

	local data = {
		lastPosition = Vector3.zero,
		strategy = strat,
		isDirty = true,
		activeGroupMemberships = {}, -- [GroupUID] = ZoneIndex
	}

	local idx = #self.Items + 1
	self.Items[idx] = item
	self.ItemIndices[item] = idx
	self.ItemData[item] = data

	State.itemToCollection[item] = self.ID

	if customData then
		if not State.itemCustomData[item] then
			State.itemCustomData[item] = {}
		end
		State.itemCustomData[item] = customData
	end

	return self
end

function Collection:Remove(item: Types.Item): Types.Collection
	if State.itemToCollection[item] ~= self.ID then
		return self
	end

	local data = self.ItemData[item]

	-- Trigger exit
	local safetyMode = self.Settings.SafetyMode
	for gUID, oldZoneIdx in pairs(data.activeGroupMemberships) do
		if State.groupTrackingItems[gUID] then
			State.groupTrackingItems[gUID][item] = nil
		end

		local cbs = State.groupExitedCallbacks[gUID]
		if cbs then
			local z = State.zoneIndexToZoneObj[oldZoneIdx]
			local cd = State.itemCustomData[item] and State.itemCustomData[item][gUID]
			for _, fn in cbs do
				if safetyMode then
					task.spawn(fn, item, z, cd)
				else
					fn(item, z, cd)
				end
			end
		end
	end

	-- Swap-Remove from Array
	local idx = self.ItemIndices[item]
	local lastIdx = #self.Items
	local lastItem = self.Items[lastIdx]

	if idx == lastIdx then
		self.Items[lastIdx] = nil
		self.ItemIndices[item] = nil
	else
		self.Items[idx] = lastItem
		self.ItemIndices[lastItem] = idx
		self.Items[lastIdx] = nil
		self.ItemIndices[item] = nil
	end

	self.ItemData[item] = nil
	State.itemToCollection[item] = nil
	State.itemCustomData[item] = nil

	return self
end

-- TODO
function Collection:GetItems(): { Types.Item }
	return {}
end

--TODO
function Collection:GetGroups(): { Types.Group }
	return {}
end

function Collection:Destroy(): ()
	for i = #self.Items, 1, -1 do
		self:Remove(self.Items[i])
	end

	State.collectionToGroups[self.ID] = nil
	State.collections[self.ID] = nil
	setmetatable(self :: any, nil)
end

return Collection
