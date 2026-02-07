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
		object.radius = halfSize.X
	elseif shape == 'Cylinder' then
		local halfHeight = halfSize.X
		object.start = object.Position - object.CFrame.RightVector * halfHeight
		object.axis = object.CFrame.RightVector
		object.axisLength = halfHeight * 2
		object.radiusSquared = halfSize.Y * halfSize.Y
	end

	local index = State.nextZoneId
	State.nextZoneId += 1
	State.objects[index] = object
	State.pendingRebuild = true

	local self = setmetatable({ Index = index, Part = associatedPart }, Zone)
	State.zoneIndexToZoneObj[index] = (self :: any) :: Types.Zone

	task.delay(5, function()
		if State.zoneIndexToZoneObj[index] and not State.zoneWatchingGroups[index] then
			warn(
				string.format(
					'[BitZone] Warning: Zone (Index %d) has been active for 5s without being bound to a Group. '
						.. 'It will not process any detections. Use :BindToGroups() to activate it.',
					index
				)
			)
		end
	end)

	return (self :: any) :: Types.Zone
end

function Zone:BindToGroups(...): Types.Zone
	local watching = State.zoneWatchingGroups[self.Index] or {}
	State.zoneWatchingGroups[self.Index] = watching
	for _, g in { ... } do
		if not table.find(watching, g.UID) then
			table.insert(watching, g.UID)
		end
	end
	State.isDirty = true
	return self
end

function Zone:UnbindFromGroups(...): Types.Zone
	local watching = State.zoneWatchingGroups[self.Index]
	if not watching then
		return self
	end

	for _, g in { ... } do
		local idx = table.find(watching, g.UID)
		while idx do
			table.remove(watching, idx)
			idx = table.find(watching, g.UID)
		end
	end
	if #watching == 0 then
		State.zoneWatchingGroups[self.Index] = nil
	end
	State.isDirty = true

	return self
end

function Zone:GetGroups(): { Types.Group }
	local watching = State.zoneWatchingGroups[self.Index]
	if not watching then
		return {}
	end

	local result = {}
	for _, uid in watching do
		local group = State.groupUIDToGroupObj[uid]
		if group then
			table.insert(result, group)
		end
	end
	return result
end

function Zone:Destroy()
	State.zoneWatchingGroups[self.Index] = nil
	State.zoneIndexToZoneObj[self.Index] = nil
	State.objects[self.Index] = nil
	State.pendingRebuild = true

	setmetatable(self :: any, nil)
end

return Zone
