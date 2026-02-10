--!strict

local Geometry = require(script.Parent.Parent.Core.Geometry)
local State = require(script.Parent.Parent.State)
local Types = require(script.Parent.Parent.Types)

local Zone = {}
Zone.__index = Zone

function Zone.new(
	cframe: CFrame,
	size: Vector3,
	shapeType: Types.ShapeType,
	associatedPart: BasePart?,
	isDynamic: boolean?
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

	local self = (
		setmetatable({ id = id, part = associatedPart, isDynamic = isDynamic or false }, Zone) :: any
	) :: Types.Zone
	State.zoneIdToZoneObj[id] = self

	return self
end

function Zone:attach(...: Types.Group): Types.Zone
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

function Zone:detach(...: Types.Group): Types.Zone
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

function Zone:update(newCFrame: CFrame?, newSize: Vector3?): Types.Zone
	local isDynamic = self.isDynamic

	local shape = isDynamic and State.dynamicShapes[self.id] or State.staticShapes[self.id]

	-- If no arguments, use reference part if possible
	if not newCFrame and self.part then
		newCFrame = self.part.CFrame
		newSize = self.part.Size
	end

	if not newCFrame or not newSize then
		warn('[QuickZone] Zone:update() failed. No Part given and no CFrame provided.')
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

	if isDynamic then
		State.pendingDynamicRebuild = true
	else
		State.pendingStaticRebuild = true
	end

	return self
end

function Zone:getObservers(): { Types.Observer }
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

function Zone:isPointInside(point: Vector3): boolean
	local shape = State.staticShapes[self.id]
	return Geometry.isPointInShape(point, shape)
end

function Zone:destroy()
	State.zoneAttachedObservers[self.id] = nil
	State.zoneIdToZoneObj[self.id] = nil
	State.staticShapes[self.id] = nil
	State.pendingStaticRebuild = true

	setmetatable(self :: any, nil)
end

return Zone
