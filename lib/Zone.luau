--!strict

local State = require(script.Parent.State)
local Types = require(script.Parent.Types)

local Zone = {}
Zone.__index = Zone

function Zone.new(cframe: CFrame, size: Vector3, shape: Types.ShapeType, associatedPart: BasePart?): Types.Zone
	local halfSize = size / 2
	local object: Types.BoundingVolume = {
		Position = cframe.Position,
		CFrame = cframe,
		HalfSize = halfSize,
		Shape = shape,
	}

	if shape == 'Ball' then
		object.RadiusSq = halfSize.X * halfSize.X
	elseif shape == 'Cylinder' then
		local halfHeight = halfSize.X
		object.Start = object.Position - object.CFrame.RightVector * halfHeight
		object.Axis = object.CFrame.RightVector
		object.AxisLength = halfHeight * 2
		object.RadiusSq = halfSize.Y * halfSize.Y
	end

	local id = State.NextZoneId
	State.NextZoneId += 1
	State.Objects[id] = object
	State.PendingRebuild = true

	local self = (setmetatable({ Id = id, Part = associatedPart }, Zone) :: any) :: Types.Zone
	State.ZoneIdToZoneObj[id] = self

	return self
end

function Zone:BindToObservers(...): Types.Zone
	local bound = State.ZoneBoundObservers[self.Id] or {}
	State.ZoneBoundObservers[self.Id] = bound
	for _, observer in { ... } do
		if not table.find(bound, observer.Id) then
			table.insert(bound, observer.Id)
		end
	end
	State.IsDirty = true
	return self
end

function Zone:UnbindFromObservers(...): Types.Zone
	local bound = State.ZoneBoundObservers[self.Id]
	if not bound then
		return self
	end

	for _, observer in { ... } do
		local idx = table.find(bound, observer.Id)
		while idx do
			table.remove(bound, idx)
			idx = table.find(bound, observer.Id)
		end
	end
	if #bound == 0 then
		State.ZoneBoundObservers[self.Id] = nil
	end
	State.IsDirty = true

	return self
end

function Zone:GetObservers(): { Types.Observer }
	local bound = State.ZoneBoundObservers[self.Id]
	if not bound then
		return {}
	end

	local result = {}
	for _, id in bound do
		local observer = State.ObserverIdToObserverObj[id]
		if observer then
			table.insert(result, observer)
		end
	end
	return result
end

function Zone:Destroy()
	State.ZoneBoundObservers[self.Id] = nil
	State.ZoneIdToZoneObj[self.Id] = nil
	State.Objects[self.Id] = nil
	State.PendingRebuild = true

	setmetatable(self :: any, nil)
end

return Zone
