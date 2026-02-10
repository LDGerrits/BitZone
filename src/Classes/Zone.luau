--!strict

local State = require(script.Parent.Parent.State)
local Types = require(script.Parent.Parent.Types)

local Zone = {}
Zone.__index = Zone

function Zone.new(cframe: CFrame, size: Vector3, shape: Types.ShapeType, associatedPart: BasePart?): Types.Zone
	local halfSize = size / 2
	local object: Types.BoundingVolume = {
		position = cframe.Position,
		cframe = cframe,
		halfSize = halfSize,
		shape = shape,
	}

	if shape == 'Ball' then
		object.radiusSq = halfSize.X * halfSize.X
	elseif shape == 'Cylinder' then
		local halfHeight = halfSize.X
		object.start = object.position - object.cframe.RightVector * halfHeight
		object.axis = object.cframe.RightVector
		object.axisLength = halfHeight * 2
		object.radiusSq = halfSize.Y * halfSize.Y
	end

	local id = State.nextZoneId
	State.nextZoneId += 1
	State.objects[id] = object
	State.pendingRebuild = true

	local self = (setmetatable({ id = id, part = associatedPart }, Zone) :: any) :: Types.Zone
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

function Zone:destroy()
	State.zoneAttachedObservers[self.id] = nil
	State.zoneIdToZoneObj[self.id] = nil
	State.objects[self.id] = nil
	State.pendingRebuild = true

	setmetatable(self :: any, nil)
end

return Zone
