--!strict

local Geometry = require(script.Parent.Parent.Core.Geometry)
local State = require(script.Parent.Parent.State)
local Types = require(script.Parent.Parent.Types)

--[=[ 
	Zones define physical areas in world space. They can be static or dynamic 
	and support shapes like Blocks, Balls, and Cylinders.
	
	Zones themselves are 'passive', meaning they must be attached to an Observer before any detection occurs.

	@class Zone
]=]
local Zone = {}
Zone.__index = Zone

function Zone.new(
	cframe: CFrame,
	size: Vector3,
	shapeType: Types.ShapeType,
	associatedPart: BasePart?,
	isDynamic: boolean?,
	metadata: any?
): Types.Zone
	local halfSize = size / 2
	local shape: Types.BoundingVolume = {
		position = cframe.Position,
		cframe = cframe,
		halfSize = halfSize,
		type = shapeType,
	}

	if shapeType == 'Ball' then
		shape.radiusSq = halfSize.X * halfSize.X
	elseif shapeType == 'Cylinder' then
		local halfHeight = halfSize.X
		shape.start = shape.position - shape.cframe.RightVector * halfHeight
		shape.axis = shape.cframe.RightVector
		shape.axisLength = halfHeight * 2
		shape.radiusSq = halfSize.Y * halfSize.Y
	end

	local id = State.nextZoneId
	State.nextZoneId += 1

	if isDynamic then
		State.dynamicShapes[id] = shape
		State.pendingDynamicRebuild = true
	else
		State.staticShapes[id] = shape
		State.pendingStaticRebuild = true
	end

	local self: Types.InternalZone =
		setmetatable({ id = id, part = associatedPart, dynamic = isDynamic or false, metadata = metadata }, Zone) :: any
	State.zoneIdToZoneObj[id] = self

	return self
end

--[=[ 
	Attaches one or more Observers to this zone. The observers will begin 
	monitoring this area for entity overlaps.

	```lua
	zone:attach(myObserver)
	```

	@method attach
	@within Zone
	@param ... Observer -- The observers to link.
	@return Zone
]=]
function Zone.attach(self: Types.InternalZone, ...: Types.InternalObserver): Types.Zone
	local attached = State.zoneAttachedObservers[self.id] or {}
	State.zoneAttachedObservers[self.id] = attached
	for _, observer in { ... } do
		if not table.find(attached, observer.id) then
			table.insert(attached, observer.id)
		end
	end
	State.isDirty = true
	return self
end

--[=[ 
	Detaches observers from this zone.

	@method detach
	@within Zone
	@param ... Observer -- The observers to unlink.
	@return Zone
]=]
function Zone.detach(self: Types.InternalZone, ...: Types.InternalObserver): Types.Zone
	local attached = State.zoneAttachedObservers[self.id]
	if not attached then
		return self
	end

	for _, observer in { ... } do
		local idx = table.find(attached, observer.id)
		while idx do
			table.remove(attached, idx)
			idx = table.find(attached, observer.id)
		end
	end
	if #attached == 0 then
		State.zoneAttachedObservers[self.id] = nil
	end
	State.isDirty = true

	return self
end

--[=[ 
	Updates the zone's position and size.

	```lua
	-- Manual update
	zone:update(CFrame.new(0, 20, 0), Vector3.new(5, 5, 5))

	-- Sync with associated part
	zone:update()
	```

	:::info Auto-Sync
	If the zone was created with an `associatedPart`, calling `update()` 
	without arguments will automatically sync the zone to that part's current 
	CFrame and Size.
	:::

	@method update
	@within Zone
	@param newCFrame CFrame? -- Optional new position/rotation.
	@param newSize Vector3? -- Optional new dimensions.
	@return Zone
]=]
function Zone.update(self: Types.InternalZone, newCFrame: CFrame?, newSize: Vector3?): Types.Zone
	local shape = self.dynamic and State.dynamicShapes[self.id] or State.staticShapes[self.id]

	-- If no arguments, use reference part if possible
	if not newCFrame and self.part then
		newCFrame = self.part.CFrame
		newSize = self.part.Size
	end

	if not newCFrame or not newSize then
		warn('[QuickZone] Zone:update failed. No Part given and no CFrame provided.')
		return self
	end

	local shapeType = shape.type
	local halfSize = newSize / 2

	-- Update the internal data struct
	shape.cframe = newCFrame
	shape.position = newCFrame.Position
	shape.halfSize = halfSize

	if shapeType == 'Ball' then
		shape.radiusSq = halfSize.X * halfSize.X
	elseif shapeType == 'Cylinder' then
		local halfHeight = halfSize.X
		shape.start = shape.position - shape.cframe.RightVector * halfHeight
		shape.axis = shape.cframe.RightVector
		shape.axisLength = halfHeight * 2
		shape.radiusSq = halfSize.Y * halfSize.Y
	end

	if self.dynamic then
		State.pendingDynamicRebuild = true
	else
		State.pendingStaticRebuild = true
	end

	return self
end

--[=[ 
	Set the metadata of the zone.

	@method setMetadata
	@within Zone
	@return number
]=]
function Zone.setMetadata(self: Types.InternalZone, metadata: any?): Types.Zone
	self.metadata = metadata
	return self
end

--[=[ 
	Returns the metadata of the zone.
	
	@method getMetadata
	@within Zone
	@return number
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
	Returns the BasePart associated with this zone, if any.

	@method getPart
	@within Zone
	@return BasePart?
]=]
function Zone.getPart(self: Types.InternalZone): BasePart?
	return self.part
end

--[=[
    Returns the current position of the zone.

    @method getPositioin
    @within Zone
    @return CFrame
]=]
function Zone.getPosition(self: Types.InternalZone): Vector3
	local shape = self.dynamic and State.dynamicShapes[self.id] or State.staticShapes[self.id]
	return shape.position
end

--[=[
    Returns the current CFrame of the zone.

    @method getCFrame
    @within Zone
    @return CFrame
]=]
function Zone.getCFrame(self: Types.InternalZone): CFrame
	local shape = self.dynamic and State.dynamicShapes[self.id] or State.staticShapes[self.id]
	return shape.cframe
end

--[=[
    Returns the full size of the zone.

    @method getSize
    @within Zone
    @return Vector3
]=]
function Zone.getSize(self: Types.InternalZone): Vector3
	local shape = self.dynamic and State.dynamicShapes[self.id] or State.staticShapes[self.id]
	return shape.halfSize * 2
end

--[=[ 
	Returns the geometric shape type of the zone.

	@method getShape
	@within Zone
	@return ShapeType
]=]
function Zone.getShape(self: Types.InternalZone): Types.ShapeType
	local shape = self.dynamic and State.dynamicShapes[self.id] or State.staticShapes[self.id]
	return shape.type
end

--[=[ 
	Returns a list of all Observers currently attached to this zone.
	
	@method getObservers
	@within Zone
	@return { Observer }
]=]
function Zone.getObservers(self: Types.InternalZone): { Types.Observer }
	local attached = State.zoneAttachedObservers[self.id]
	if not attached then
		return {}
	end

	local result = {}
	for _, id in attached do
		local observer = State.observerIdToObserverObj[id]
		if observer then
			table.insert(result, observer)
		end
	end
	return result
end

--[=[ 
	Checks if a point is inside this specific zone.

	@method isPointInside
	@within Zone
	@param point Vector3
	@return boolean
]=]
function Zone.isPointInside(self: Types.InternalZone, point: Vector3): boolean
	local shape = self.dynamic and State.dynamicShapes[self.id] or State.staticShapes[self.id]
	return Geometry.isPointInShape(point, shape)
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
	Cleans up the zone, removes it from the LBVH tree, and detaches all observers.
	
	@tag Destructor
	@method destroy
	@within Zone
]=]
function Zone.destroy(self: Types.InternalZone): ()
	State.zoneAttachedObservers[self.id] = nil
	State.zoneIdToZoneObj[self.id] = nil

	if self.dynamic then
		State.dynamicShapes[self.id] = nil
		State.pendingDynamicRebuild = true
	else
		State.staticShapes[self.id] = nil
		State.pendingStaticRebuild = true
	end

	setmetatable(self :: any, nil)
end

return Zone
