--!strict
--[=[
	@class Zone
	
	Zones define physical areas in world space. They can be static or dynamic 
	and support shapes like Blocks, Balls, and Cylinders.
	
	Zones themselves are 'passive', meaning they must be attached to an Observer before any detection occurs.

	:::caution Performance
	If a zone moves (e.g., attached to a moving platform) or changes size, 
	you should make the zone dynamic by setting `isDynamic` to `true`. 

	Static zones are optimized into a large, pre-calculated tree. Updating a 
	static zone forces a full recalculation of that tree, which is expensive. 
	Dynamic zones are handled separately and are much cheaper to update.
	:::
]=]

local CollectionService = game:GetService('CollectionService')

local State = require(script.Parent.Parent.Core.State)
local Types = require(script.Parent.Parent.Types)
local Geometry = require(script.Parent.Parent.Utils.Geometry)
local Log = require(script.Parent.Parent.Utils.Log)
local Zones = require(script.Parent.Zones)

local staticCFrames = State.staticCFrames
local staticHalfSizes = State.staticHalfSizes
local staticTypes = State.staticTypes
local dynamicCFrames = State.dynamicCFrames
local dynamicHalfSizes = State.dynamicHalfSizes
local dynamicTypes = State.dynamicTypes

local isPointInShape = Geometry.isPointInShape

local SHAPE_MAP = {
	Block = Enum.PartType.Block.Value,
	Cylinder = Enum.PartType.Cylinder.Value,
	Ball = Enum.PartType.Ball.Value,
	Wedge = Enum.PartType.Wedge.Value,
	CornerWedge = Enum.PartType.CornerWedge.Value,
}

local function getShapeEnumValue(part: BasePart): number
	if part:IsA('Part') then
		return part.Shape.Value
	end

	if part:IsA('WedgePart') then
		return Enum.PartType.Wedge.Value
	end

	if part:IsA('CornerWedgePart') then
		return Enum.PartType.CornerWedge.Value
	end

	return Enum.PartType.Block.Value
end

local function clearAutoSync(zone: Types.InternalZone)
	State.autoSyncZones[zone.id] = nil
	if zone.syncConnections then
		for _, conn in zone.syncConnections do
			conn:Disconnect()
		end
		zone.syncConnections = nil
	end
end

local function setupAutoSync(zone: Types.InternalZone, reference: BasePart | Attachment | Bone)
	State.autoSyncZones[zone.id] = zone

	local connections = zone.syncConnections or {}

	if reference:IsA('BasePart') then
		table.insert(
			connections,
			reference:GetPropertyChangedSignal('Size'):Connect(function()
				local newHalfSize = reference.ExtentsSize * 0.5
				if dynamicHalfSizes[zone.id] ~= newHalfSize then
					dynamicHalfSizes[zone.id] = newHalfSize
					State.pendingDynamicRebuild = true
				end
			end)
		)
	end

	if reference:IsA('Part') then
		table.insert(
			connections,
			reference:GetPropertyChangedSignal('Shape'):Connect(function()
				local newShape = reference.Shape.Value
				if dynamicTypes[zone.id] ~= newShape then
					dynamicTypes[zone.id] = newShape
					State.pendingDynamicRebuild = true
				end
			end)
		)
	end

	zone.syncConnections = connections
	zone:sync()
end

local function updateObserverZoneCount(observerId: number, isDynamic: boolean, delta: number)
	local dict = isDynamic and State.observerDynamicCount or State.observerStaticCount
	local current = dict[observerId] or 0
	local newCount = current + delta
	dict[observerId] = newCount

	-- Only flag entities dirty if the observer's topology fundamentally changed
	if (current == 0 and newCount == 1) or (current == 1 and newCount == 0) then
		-- Only force a global logic override when an observer loses its last zone
		if current == 1 and newCount == 0 then
			State.logicVersion += 1
		end

		for groupId, observers in State.groupToObservers do
			if not observers[observerId] then
				continue
			end

			local group = State.groups[groupId]
			if not group then
				continue
			end

			for _, entity in group.entities do
				State.dirtyTopology[entity] = true
			end
		end
	end
end

local Zone = {}
Zone.__index = Zone

local function newZoneInternal(
	cframe: CFrame,
	size: Vector3,
	shapeType: number,
	reference: (BasePart | Attachment | Bone)?,
	isDynamic: boolean,
	metadata: any?,
	autoSync: boolean
): Types.Zone
	local id = State.nextZoneId
	State.nextZoneId += 1

	local halfSize = size * 0.5
	if isDynamic then
		State.dynamicCFrames[id] = cframe
		State.dynamicHalfSizes[id] = halfSize
		State.dynamicTypes[id] = shapeType
		State.pendingDynamicRebuild = true
	else
		State.staticCFrames[id] = cframe
		State.staticHalfSizes[id] = halfSize
		State.staticTypes[id] = shapeType
		State.pendingStaticRebuild = true
	end

	local self: Types.InternalZone = setmetatable({
		id = id,
		reference = reference,
		dynamic = isDynamic,
		metadata = metadata,
		autoSync = false,
	}, Zone) :: any
	State.zoneIdToZoneObj[id] = self

	if autoSync then
		self:setAutoSync(true)
	end

	return self
end

--[=[ 
	Creates a Zone object.

	```lua
	local zone = QuickZone.Zone({
		cframe = CFrame.new(0, 10, 0),
		size = Vector3.new(10, 10, 10),
		shape = 'Block',
		isDynamic = false,
		metadata = { Name = "Lobby" },
		observers = { observer1, observer2 }
	})
	```

	:::caution Dynamic Zones
	If a zone moves, set `isDynamic` to `true` for maximum performance. 
	:::

	:::caution Rebuild Request
	Requests a rebuild of corresponding tree (batched per frame).
	:::

	@tag Constructor
	@tag Chainable
	@param config { cframe: CFrame, size: Vector3, shape: Types.ShapeType?, reference: (BasePart | Attachment | Bone)?, isDynamic: boolean?, metadata: any?, autoSync: boolean? }?
	@return Zone
]=]
function Zone.new(config: {
	cframe: CFrame,
	size: Vector3,
	shape: Types.ShapeType?,
	reference: (BasePart | Attachment | Bone)?,
	isDynamic: boolean?,
	metadata: any?,
	autoSync: boolean?,
}): Types.Zone
	local shapeType = Enum.PartType.Block.Value

	if config.shape then
		local mapped = SHAPE_MAP[config.shape]
		if mapped then
			shapeType = mapped
		else
			Log.warn("Invalid shape '%s'. Defaulting to Block.", nil, tostring(config.shape))
		end
	end

	return newZoneInternal(
		config.cframe,
		config.size,
		shapeType,
		config.reference,
		config.isDynamic or false,
		config.metadata,
		config.autoSync or false
	)
end

--[=[ 
	Creates a Zone automatically based on the Part's properties.
	Supported shapes: Block, Ball (Spheres), Cylinder, Wedge, and CornerWedge.

	```lua
	local part = workspace.ZonePart
	local zone = QuickZone.Zone.fromPart(part, { 
		observers = { safeObserver, healingObserver } 
	})
	```

	:::caution Dynamic Zones
	If a zone moves, set `isDynamic` to `true` for maximum performance. 
	:::

	:::caution Rebuild Request
	Requests a rebuild of corresponding tree (batched per frame).
	:::

	@tag Constructor
	@tag Chainable
	@param part BasePart -- The part to derive the zone from.
	@param config { isDynamic: boolean?, metadata: any?, autoSync: boolean? }?
	@return Zone
]=]
function Zone.fromPart(
	part: BasePart,
	config: {
		isDynamic: boolean?,
		metadata: any?,
		autoSync: boolean?,
	}?
): Types.Zone
	local shapeId = Enum.PartType.Block.Value
	if part:IsA('Part') then
		shapeId = part.Shape.Value
	elseif part:IsA('WedgePart') then
		shapeId = Enum.PartType.Wedge.Value
	elseif part:IsA('CornerWedgePart') then
		shapeId = Enum.PartType.CornerWedge.Value
	end

	local isDynamic = config and config.isDynamic or false
	local metadata = config and config.metadata
	local autoSync = config and config.autoSync or false

	return newZoneInternal(part.CFrame, part.ExtentsSize, shapeId, part, isDynamic, metadata, autoSync)
end

--[=[
	Creates and manages a collection of Zones from a static array of BaseParts.
	
	@tag Constructor
	@tag Chainable
	@within Zone
	@param parts { BasePart }
	@param config { isDynamic: boolean?, metadata: any?, autoSync: boolean? }?
	@return Zones
]=]
function Zone.fromParts(
	parts: { BasePart },
	config: {
		isDynamic: boolean?,
		metadata: any?,
		autoSync: boolean?,
	}?
): Types.Zones
	local isDynamic = if config and config.isDynamic ~= nil then config.isDynamic else false
	local metadata = if config and config.metadata ~= nil then config.metadata else nil
	local autoSync = if config and config.autoSync ~= nil then config.autoSync else false

	local zones = Zones.new({
		isDynamic = isDynamic,
		metadata = metadata,
		autoSync = autoSync,
	}) :: Types.InternalZones

	for _, part in parts do
		if part:IsA('BasePart') then
			local newZone = Zone.fromPart(part, {
				isDynamic = isDynamic,
				metadata = zones.metadata,
				autoSync = autoSync,
			})
			zones:add(newZone)
		end
	end

	return zones
end

--[=[
	Dynamically creates and manages a Zones object from all BaseParts that are 
	direct children of the given Instance. Automatically updates as children are added/removed.
	
	@tag Constructor
	@tag Chainable
	@within Zone
	@param parent Instance
	@param config { isDynamic: boolean?, metadata: any?, autoSync: boolean? }?
	@return Zones
]=]
function Zone.fromChildren(
	parent: Instance,
	config: {
		isDynamic: boolean?,
		metadata: any?,
		autoSync: boolean?,
	}?
): Types.Zones
	local isDynamic = if config and config.isDynamic ~= nil then config.isDynamic else false
	local metadata = if config and config.metadata ~= nil then config.metadata else nil
	local autoSync = if config and config.autoSync ~= nil then config.autoSync else false

	local zones = Zones.new({
		isDynamic = isDynamic,
		metadata = metadata,
		autoSync = autoSync,
	}) :: Types.InternalZones

	local instanceToZone = {} :: { [Instance]: Types.Zone }

	local function onAdded(child: Instance)
		if child:IsA('BasePart') and not instanceToZone[child] then
			local newZone = Zone.fromPart(child, {
				isDynamic = isDynamic,
				metadata = zones.metadata,
			})
			instanceToZone[child] = newZone
			zones:add(newZone)
		end
	end

	local function onRemoved(child: Instance)
		local oldZone = instanceToZone[child]
		if oldZone then
			instanceToZone[child] = nil
			oldZone:destroy()
		end
	end

	local addedConn = parent.ChildAdded:Connect(onAdded)
	local removedConn = parent.ChildRemoved:Connect(onRemoved)
	for _, child in parent:GetChildren() do
		onAdded(child)
	end

	zones:onDestroy(function()
		addedConn:Disconnect()
		removedConn:Disconnect()
		for child, _ in instanceToZone do
			onRemoved(child)
		end
		table.clear(instanceToZone)
	end)

	return zones
end

--[=[
	Dynamically creates and manages a Zones object from all BaseParts contained 
	anywhere within the given Instance. Automatically updates as descendants are added/removed.
	
	```lua
	local mapZones = QuickZone.Zone.fromDescendants(workspace.HazardFolder, {
		observers = { hazardObserver }
	})
	```
	
	@tag Constructor
	@tag Chainable
	@within Zone
	@param parent Instance -- The container (Model, Folder, etc.) to search through.
	@param config { isDynamic: boolean?, metadata: any?, autoSync: boolean? }?
	@return Zones
]=]
function Zone.fromDescendants(
	parent: Instance,
	config: {
		isDynamic: boolean?,
		metadata: any?,
		autoSync: boolean?,
	}?
): Types.Zones
	local isDynamic = if config and config.isDynamic ~= nil then config.isDynamic else false
	local metadata = if config and config.metadata ~= nil then config.metadata else nil
	local autoSync = if config and config.autoSync ~= nil then config.autoSync else false

	local zones = Zones.new({
		isDynamic = isDynamic,
		metadata = metadata,
		autoSync = autoSync,
	}) :: Types.InternalZones

	local instanceToZone = {} :: { [Instance]: Types.Zone }

	local function onAdded(descendant: Instance)
		if descendant:IsA('BasePart') and not instanceToZone[descendant] then
			local newZone = Zone.fromPart(descendant, {
				isDynamic = isDynamic,
				metadata = zones.metadata,
			})
			instanceToZone[descendant] = newZone
			zones:add(newZone)
		end
	end

	local function onRemoved(descendant: Instance)
		local oldZone = instanceToZone[descendant]
		if oldZone then
			instanceToZone[descendant] = nil
			oldZone:destroy()
		end
	end

	local addedConn = parent.DescendantAdded:Connect(onAdded)
	local removedConn = parent.DescendantRemoving:Connect(onRemoved)
	for _, descendant in parent:GetDescendants() do
		onAdded(descendant)
	end

	zones:onDestroy(function()
		addedConn:Disconnect()
		removedConn:Disconnect()
		for descendant, _ in instanceToZone do
			onRemoved(descendant)
		end
		table.clear(instanceToZone)
	end)

	return zones
end

--[=[
	Dynamically creates and manages Zones for all BaseParts with a specific CollectionService tag.
	If the tag is applied to a container (e.g., a Model or a Folder), it will create zones for all BasePart descendants.
	
	@tag Constructor
	@tag Chainable
	@within Zone
	@param tag string
	@param config { isDynamic: boolean?, metadata: any?, autoSync: boolean? }?
	@return Zones
]=]
function Zone.fromTag(
	tag: string,
	config: {
		isDynamic: boolean?,
		metadata: any?,
		autoSync: boolean?,
	}?
): Types.Zones
	local isDynamic = if config and config.isDynamic ~= nil then config.isDynamic else false
	local metadata = if config and config.metadata ~= nil then config.metadata else nil
	local autoSync = if config and config.autoSync ~= nil then config.autoSync else false

	local zones = Zones.new({
		isDynamic = isDynamic,
		metadata = metadata,
		autoSync = autoSync,
	}) :: Types.InternalZones

	local watchingAncestry = {} :: { [Instance]: RBXScriptConnection }
	local containerConnections = {} :: { [Instance]: { RBXScriptConnection } }
	local instanceToZone = {} :: { [BasePart]: Types.Zone }
	local partRefCount = {} :: { [BasePart]: number }

	local function addPart(part: BasePart)
		local count = (partRefCount[part] or 0) + 1
		partRefCount[part] = count

		-- Only create the zone if this is the first time
		if count == 1 then
			local newZone = Zone.fromPart(part, {
				isDynamic = isDynamic,
				metadata = zones.metadata,
				autoSync = autoSync,
			})
			instanceToZone[part] = newZone
			zones:add(newZone)
		end
	end

	local function removePart(part: BasePart)
		local count = (partRefCount[part] or 0) - 1

		if count <= 0 then -- No more active tags claim this part, so safe to destroy
			partRefCount[part] = nil
			local deadZone = instanceToZone[part]
			if deadZone then
				instanceToZone[part] = nil
				deadZone:destroy()
			end
		else
			partRefCount[part] = count
		end
	end

	local function processTaggedInstance(instance: Instance)
		local inWorkspace = instance:IsDescendantOf(workspace)
		if inWorkspace then
			if instance:IsA('BasePart') then
				addPart(instance)
			else
				if not containerConnections[instance] then
					local addedConn = instance.DescendantAdded:Connect(function(descendant)
						if descendant:IsA('BasePart') then
							addPart(descendant)
						end
					end)
					local removedConn = instance.DescendantRemoving:Connect(function(descendant)
						if descendant:IsA('BasePart') then
							removePart(descendant)
						end
					end)
					containerConnections[instance] = { addedConn, removedConn }

					for _, descendant in instance:GetDescendants() do
						if descendant:IsA('BasePart') then
							addPart(descendant)
						end
					end
				end
			end
		else
			if instance:IsA('BasePart') then
				removePart(instance)
			else
				local conns = containerConnections[instance]
				if conns then
					conns[1]:Disconnect()
					conns[2]:Disconnect()
					containerConnections[instance] = nil
				end
				for _, descendant in instance:GetDescendants() do
					if descendant:IsA('BasePart') then
						removePart(descendant)
					end
				end
			end
		end
	end

	local function startWatching(instance: Instance)
		if watchingAncestry[instance] then
			return
		end
		watchingAncestry[instance] = instance.AncestryChanged:Connect(function()
			processTaggedInstance(instance)
		end)
		processTaggedInstance(instance)
	end

	local function stopWatching(instance: Instance)
		local conn = watchingAncestry[instance]
		if conn then
			conn:Disconnect()
			watchingAncestry[instance] = nil
		end

		if instance:IsA('BasePart') then
			removePart(instance)
		else
			local conns = containerConnections[instance]
			if conns then
				conns[1]:Disconnect()
				conns[2]:Disconnect()
				containerConnections[instance] = nil
			end
			for _, descendant in instance:GetDescendants() do
				if descendant:IsA('BasePart') then
					removePart(descendant)
				end
			end
		end
	end

	local addedConn = CollectionService:GetInstanceAddedSignal(tag):Connect(startWatching)
	local removedConn = CollectionService:GetInstanceRemovedSignal(tag):Connect(stopWatching)
	for _, instance in CollectionService:GetTagged(tag) do
		startWatching(instance)
	end

	zones:onDestroy(function()
		addedConn:Disconnect()
		removedConn:Disconnect()
		for inst in watchingAncestry do
			stopWatching(inst)
		end
		table.clear(watchingAncestry)
		table.clear(containerConnections)
		table.clear(instanceToZone)
		table.clear(partRefCount)
	end)

	return zones
end

function Zone.attach(self: Types.InternalZone, observer: Types.InternalObserver): Types.Zone
	local attached = State.zoneAttachedObservers[self.id] or {}
	State.zoneAttachedObservers[self.id] = attached

	if not table.find(attached, observer.id) then
		table.insert(attached, observer.id)
		updateObserverZoneCount(observer.id, self.dynamic, 1)
	end

	if self.dynamic then
		State.dynamicVersion += 1
	else
		State.staticVersion += 1
	end

	return self
end

function Zone.detach(self: Types.InternalZone, observer: Types.InternalObserver): Types.Zone
	local attached = State.zoneAttachedObservers[self.id]
	if not attached then
		return self
	end

	local idx = table.find(attached, observer.id)
	if idx then
		local lastIdx = #attached
		if idx ~= lastIdx then
			attached[idx] = attached[lastIdx]
		end
		attached[lastIdx] = nil
		updateObserverZoneCount(observer.id, self.dynamic, -1)
	end

	if #attached == 0 then
		State.zoneAttachedObservers[self.id] = nil
	end

	if self.dynamic then
		State.dynamicVersion += 1
	else
		State.staticVersion += 1
	end

	return self
end

--[=[ 
	Enables or disables automatic polling and syncing to the tracked BasePart.
	If the zone is currently static, it will automatically be set to dynamic.

	@tag Chainable
	@method setAutoSync
	@within Zone
	@param autoSync boolean
	@return Zone
]=]
function Zone.setAutoSync(self: Types.InternalZone, autoSync: boolean): Types.Zone
	if self.autoSync == autoSync then
		return self
	end

	self.autoSync = autoSync
	if autoSync then
		if not self.dynamic then
			self:setDynamic(true)
		end

		if self.reference then
			setupAutoSync(self, self.reference)
		else
			Log.warn('Cannot autoSync Zone %d without a tracked reference.', nil, self.id)
		end
	else
		clearAutoSync(self)
	end

	return self
end

--[=[ 
	Updates the tracked reference for this zone. If `autoSync` is enabled, 
	the zone will immediately start syncing to the new reference.

	@tag Chainable
	@method setReference
	@within Zone
	@param reference (BasePart | Attachment | Bone)?
	@return Zone
]=]
function Zone.setReference(self: Types.InternalZone, reference: (BasePart | Attachment | Bone)?): Types.Zone
	self.reference = reference

	if self.autoSync then
		clearAutoSync(self)
		if reference then
			setupAutoSync(self, reference)
		end
	end

	return self
end

--[=[ 
	Update the zone to the reference. For a part-based zone, this will sync the zone's 
	CFrame, Size and Shape to match the reference's. For attachment/bone-based zones, 
	only the WorldCFrame is synced.

	:::info Rebuild
	This method flags the zone for an update. The actual tree rebuild is batched and occurs once per frame.
	* Static Zones: Expensive. Forces a rebuild of the main static tree.
	* Dynamic Zones: Cheap. Forces a rebuild of the smaller dynamic tree.
	:::

	@tag Chainable
	@method sync
	@within Zone
	@return Zone
]=]
function Zone.sync(self: Types.InternalZone): Types.Zone
	local reference = self.reference
	if not reference then
		Log.warn('Zone:sync failed for Zone %d. No reference found.', nil, self.id)
		return self
	end

	local id = self.id

	if reference:IsA('BasePart') then
		local newCFrame = reference.CFrame
		local newHalfSize = reference.ExtentsSize * 0.5
		local newShape = getShapeEnumValue(reference)

		if self.dynamic then
			local needsUpdate = false

			if dynamicCFrames[id] ~= newCFrame then
				dynamicCFrames[id] = newCFrame
				needsUpdate = true
			end

			if dynamicHalfSizes[id] ~= newHalfSize then
				dynamicHalfSizes[id] = newHalfSize
				needsUpdate = true
			end

			if dynamicTypes[id] ~= newShape then
				dynamicTypes[id] = newShape
				needsUpdate = true
			end

			if needsUpdate then
				State.pendingDynamicRebuild = true
			end
		else
			local needsUpdate = false

			if staticCFrames[id] ~= newCFrame then
				staticCFrames[id] = newCFrame
				needsUpdate = true
			end

			if staticHalfSizes[id] ~= newHalfSize then
				staticHalfSizes[id] = newHalfSize
				needsUpdate = true
			end

			if staticTypes[id] ~= newShape then
				staticTypes[id] = newShape
				needsUpdate = true
			end

			if needsUpdate then
				State.pendingStaticRebuild = true
			end
		end

		return self
	end

	if reference:IsA('Attachment') or reference:IsA('Bone') then
		local newCFrame = reference.WorldCFrame
		if self.dynamic then
			if dynamicCFrames[id] == newCFrame then
				return self
			end

			dynamicCFrames[id] = newCFrame
			State.pendingDynamicRebuild = true
		else
			if staticCFrames[id] == newCFrame then
				return self
			end

			staticCFrames[id] = newCFrame
			State.pendingStaticRebuild = true
		end

		return self
	end

	return self
end

--[=[ 
	Promotes or demotes a zone between the Static and Dynamic trees.
	
	:::info Performance
	Changing a zone's dynamic state forces both the static and dynamic trees to rebuild. 
	Use this sparingly (e.g., when a static bridge breaks and becomes dynamic).
	:::

	@tag Chainable
	@method setDynamic
	@within Zone
	@param isDynamic boolean
	@return Zone
]=]
function Zone.setDynamic(self: Types.InternalZone, isDynamic: boolean): Types.Zone
	if self.dynamic == isDynamic then
		return self
	end

	local id = self.id
	self.dynamic = isDynamic

	local attached = State.zoneAttachedObservers[id]
	if attached then
		for _, obsId in attached do
			updateObserverZoneCount(obsId, not isDynamic, -1)
			updateObserverZoneCount(obsId, isDynamic, 1)
		end
	end

	if isDynamic then
		dynamicCFrames[id] = staticCFrames[id]
		dynamicHalfSizes[id] = staticHalfSizes[id]
		dynamicTypes[id] = staticTypes[id]

		staticCFrames[id] = nil
		staticHalfSizes[id] = nil
		staticTypes[id] = nil
	else
		if self.autoSync then
			self:setAutoSync(false)
		end

		staticCFrames[id] = dynamicCFrames[id]
		staticHalfSizes[id] = dynamicHalfSizes[id]
		staticTypes[id] = dynamicTypes[id]

		dynamicCFrames[id] = nil
		dynamicHalfSizes[id] = nil
		dynamicTypes[id] = nil
	end

	State.pendingStaticRebuild = true
	State.pendingDynamicRebuild = true

	return self
end

--[=[ 
	Updates the Zone's CFrame.

	:::caution Rebuild Request
	Requests a rebuild of corresponding tree (batched per frame).
	:::

	@tag Chainable
	@method setCFrame
	@within Zone
	@param cf CFrame
	@return Zone
]=]
function Zone.setCFrame(self: Types.InternalZone, cf: CFrame): Types.Zone
	if self.dynamic then
		dynamicCFrames[self.id] = cf
		State.pendingDynamicRebuild = true
	else
		staticCFrames[self.id] = cf
		State.pendingStaticRebuild = true
	end
	return self
end

--[=[ 
	Updates the Zone's Position while preserving its current Rotation.

	:::caution Rebuild Request
	Requests a rebuild of corresponding tree (batched per frame).
	:::

	@tag Chainable
	@method setPosition
	@within Zone
	@param pos Vector3
	@return Zone
]=]
function Zone.setPosition(self: Types.InternalZone, pos: Vector3): Types.Zone
	local currentCF = self.dynamic and dynamicCFrames[self.id] or staticCFrames[self.id]
	local newCF = currentCF.Rotation + pos
	return self:setCFrame(newCF)
end

--[=[ 
	Updates the Zone's Size.

	:::caution Rebuild Request
	Requests a rebuild of corresponding tree (batched per frame).
	:::
	
	@tag Chainable
	@method setSize
	@within Zone
	@param size Vector3
	@return Zone
]=]
function Zone.setSize(self: Types.InternalZone, size: Vector3): Types.Zone
	local halfSize = size * 0.5

	if self.dynamic then
		dynamicHalfSizes[self.id] = halfSize
		State.pendingDynamicRebuild = true
	else
		staticHalfSizes[self.id] = halfSize
		State.pendingStaticRebuild = true
	end
	return self
end

--[=[ 
	Updates the Zone's geometric shape.
	
	@tag Chainable
	@method setShape
	@within Zone
	@param shape ShapeType
	@return Zone
]=]
function Zone.setShape(self: Types.InternalZone, shape: Types.ShapeType): Types.Zone
	local shapeType = Enum.PartType.Block.Value

	local mapped = SHAPE_MAP[shape]
	if mapped then
		shapeType = mapped
	else
		Log.warn("Invalid shape '%s'. Defaulting to Block.", nil, tostring(shape))
	end

	if self.dynamic then
		dynamicTypes[self.id] = shapeType
	else
		staticTypes[self.id] = shapeType
	end

	if self.dynamic then
		State.dynamicVersion += 1
	else
		State.staticVersion += 1
	end

	return self
end

--[=[ 
	Set the metadata of the zone.

	@tag Chainable
	@method setMetadata
	@within Zone
	@param metadata any?
	@return Zone
]=]
function Zone.setMetadata(self: Types.InternalZone, metadata: any?): Types.Zone
	self.metadata = metadata
	return self
end

--[=[ 
	Returns the metadata of the zone.
	
	@method getMetadata
	@within Zone
	@return any?
]=]
function Zone.getMetadata(self: Types.InternalZone): any?
	return self.metadata
end

--[=[ 
	Returns the unique internal ID of the zone.

	@method getId
	@within Zone
	@return number
]=]
function Zone.getId(self: Types.InternalZone): number
	return self.id
end

--[=[
	Returns the reference associated with this zone, if any.

	@method getReference
	@within Zone
	@return (BasePart | Attachment | Bone)?
]=]
function Zone.getReference(self: Types.InternalZone): (BasePart | Attachment | Bone)?
	return self.reference
end

--[=[
	Returns the current position of the zone.

	@method getPosition
	@within Zone
	@return Vector3
]=]
function Zone.getPosition(self: Types.InternalZone): Vector3
	local cf = self.dynamic and dynamicCFrames[self.id] or staticCFrames[self.id]
	return cf.Position
end

--[=[
	Returns the current CFrame of the zone.

	@method getCFrame
	@within Zone
	@return CFrame
]=]
function Zone.getCFrame(self: Types.InternalZone): CFrame
	return self.dynamic and dynamicCFrames[self.id] or staticCFrames[self.id]
end

--[=[
	Returns the full size of the zone.

	@method getSize
	@within Zone
	@return Vector3
]=]
function Zone.getSize(self: Types.InternalZone): Vector3
	local halfSize = self.dynamic and dynamicHalfSizes[self.id] or staticHalfSizes[self.id]
	return halfSize * 2
end

--[=[ 
	Returns the geometric shape type of the zone.

	@method getShape
	@within Zone
	@return ShapeType
]=]
function Zone.getShape(self: Types.InternalZone): Types.ShapeType
	local shapeType = self.dynamic and dynamicTypes[self.id] or staticTypes[self.id]
	if shapeType == Enum.PartType.Block.Value then
		return 'Block'
	elseif shapeType == Enum.PartType.Ball.Value then
		return 'Ball'
	elseif shapeType == Enum.PartType.Cylinder.Value then
		return 'Cylinder'
	elseif shapeType == Enum.PartType.Wedge.Value then
		return 'Wedge'
	elseif shapeType == Enum.PartType.CornerWedge.Value then
		return 'CornerWedge'
	end
	return 'Block'
end

--[=[ 
	Checks if a point is inside this specific zone.

	@method isPointInside
	@within Zone
	@param point Vector3
	@return boolean
]=]
function Zone.isPointInside(self: Types.InternalZone, point: Vector3): boolean
	local id = self.id
	if self.dynamic then
		return isPointInShape(point, dynamicCFrames[id], dynamicHalfSizes[id], dynamicTypes[id])
	else
		return isPointInShape(point, staticCFrames[id], staticHalfSizes[id], staticTypes[id])
	end
end

--[=[ 
	Returns whether the zone is currently registered as a dynamic object.
	
	@method isDynamic
	@within Zone
	@return boolean
]=]
function Zone.isDynamic(self: Types.InternalZone): boolean
	return self.dynamic
end

--[=[ 
	Fires when `destroy()` is called on the zone

	```lua
	local disconnect = myZone:onDestroy(function()
		print('Zone was destroyed!')
	end)
	```

	@tag Event
	@method onDestroy
	@within Zone
	@param callback () -> ()
	@return () -> () -- Disconnect function
]=]
function Zone.onDestroy(self: Types.InternalZone, callback: () -> ()): () -> ()
	if not self.onDestroyCallbacks then
		self.onDestroyCallbacks = {}
	end

	table.insert(self.onDestroyCallbacks :: any, callback)

	return function()
		local idx = table.find(self.onDestroyCallbacks :: any, callback)
		if idx then
			table.remove(self.onDestroyCallbacks :: any, idx)
		end
	end
end

--[=[ 
	Cleans up the zone, removes it from the LBVH tree, and detaches all observers.

	:::caution Rebuild Request
	Requests a rebuild of corresponding tree (batched per frame).
	:::
	
	@tag Destructor
	@method destroy
	@within Zone
]=]
function Zone.destroy(self: Types.InternalZone): ()
	clearAutoSync(self)

	-- Force flush so the zone object will not be nil when spatial query is done in the Scheduler
	local id = self.id
	local attachedObservers = State.zoneAttachedObservers[id]
	if attachedObservers then
		for _, observerId in attachedObservers do
			updateObserverZoneCount(observerId, self.dynamic, -1)

			local trackedEntities = State.observerTrackingEntities[observerId]
			if not trackedEntities then
				continue
			end

			for entity, _ in trackedEntities do
				local data = State.entityData[entity]

				if not data or data.activeObserverMemberships[observerId] ~= id then
					continue
				end

				data.activeObserverMemberships[observerId] = nil
				trackedEntities[entity] = nil

				local cbs = State.observerExitedCallbacks[observerId]
				if not cbs then
					continue
				end

				local safety = State.observerSafety[observerId]
				local ref = State.entityToReference[entity] or entity
				for _, fn in cbs do
					if safety then
						task.spawn(fn, ref, self, entity)
					else
						fn(ref, self, entity)
					end
				end
			end
		end
	end

	-- Clear the reference before the onDestroyCallbacks are fired.
	-- This is to ensure that, when the callback attempts to detach the observer manually,
	-- it safely early-returns without double-decrementing the count.
	State.zoneAttachedObservers[id] = nil

	if self.onDestroyCallbacks then
		-- The table must be cloned to avoid iterator shifts
		local onDestroyCallbacks = table.clone(self.onDestroyCallbacks)
		for _, callback in onDestroyCallbacks do
			task.spawn(callback)
		end
		table.clear(self.onDestroyCallbacks)
	end

	State.zoneIdToZoneObj[id] = nil

	if self.dynamic then
		dynamicCFrames[id] = nil
		dynamicHalfSizes[id] = nil
		dynamicTypes[id] = nil
		State.pendingDynamicRebuild = true
	else
		staticCFrames[id] = nil
		staticHalfSizes[id] = nil
		staticTypes[id] = nil
		State.pendingStaticRebuild = true
	end

	setmetatable(self :: any, nil)
end

return Zone
