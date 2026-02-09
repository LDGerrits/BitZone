--!native
--!strict

local Types = require(script.Parent.Types)

local MORTON_SHIFT16_MASK = 0xFF0000FF
local MORTON_SHIFT8_MASK = 0xF00F00F
local MORTON_SHIFT4_MASK = 0x30C30C3
local MORTON_SHIFT2_MASK = 0x9249249

local expandLUT = table.create(1024)
for i = 0, 1023 do
	local value = i
	value = bit32.bor(bit32.lshift(value, 16), value)
	value = bit32.band(value, MORTON_SHIFT16_MASK)
	value = bit32.bor(bit32.lshift(value, 8), value)
	value = bit32.band(value, MORTON_SHIFT8_MASK)
	value = bit32.bor(bit32.lshift(value, 4), value)
	value = bit32.band(value, MORTON_SHIFT4_MASK)
	value = bit32.bor(bit32.lshift(value, 2), value)
	value = bit32.band(value, MORTON_SHIFT2_MASK)
	expandLUT[i + 1] = value
end

local function expandBits(value: number): number
	return expandLUT[bit32.band(value, 0x3FF) + 1]
end

local Geometry = {}

function Geometry.unionBounds(minA: Vector3, maxA: Vector3, minB: Vector3, maxB: Vector3): (Vector3, Vector3)
	return vector.min(minA, minB), vector.max(maxA, maxB)
end

function Geometry.getObjectBounds(object: Types.BoundingVolume): (Vector3, Vector3)
	local halfSize = object.HalfSize
	local cframe = object.CFrame
	local center = object.Position

	local halfExtent = vector.abs(cframe.RightVector) * halfSize.X
		+ vector.abs(cframe.UpVector) * halfSize.Y
		+ vector.abs(cframe.LookVector) * halfSize.Z

	return center - halfExtent, center + halfExtent
end

function Geometry.positionToMortonCode(position: Vector3, sceneMin: Vector3, sceneMax: Vector3): number
	local size = sceneMax - sceneMin
	local scaleX = 1023 / size.X
	local scaleY = 1023 / size.Y
	local scaleZ = 1023 / size.Z

	local localPos = position - sceneMin
	local x = math.floor(math.clamp(localPos.X * scaleX, 0, 1023))
	local y = math.floor(math.clamp(localPos.Y * scaleY, 0, 1023))
	local z = math.floor(math.clamp(localPos.Z * scaleZ, 0, 1023))

	return bit32.bor(expandBits(x), bit32.lshift(expandBits(y), 1), bit32.lshift(expandBits(z), 2))
end

function Geometry.isPointInShape(point: Vector3, object: Types.BoundingVolume): boolean
	if object.Shape == 'Block' then
		local localPoint = vector.abs(object.CFrame:PointToObjectSpace(point))
		return vector.min(localPoint, object.HalfSize) == localPoint
	elseif object.Shape == 'Ball' then
		return vector.dot(object.Position - point, object.Position - point) <= object.RadiusSq
	elseif object.Shape == 'Cylinder' then
		local toPoint = point - object.Start :: Vector3
		local projection = vector.dot(toPoint, object.Axis :: Vector3)

		if projection >= 0 and projection <= object.AxisLength :: number then
			local closestPointOnAxis = object.Start :: Vector3 + object.Axis :: Vector3 * projection
			local distanceSq = vector.dot(point - closestPointOnAxis, point - closestPointOnAxis)
			return distanceSq <= object.RadiusSq :: number
		end
		return false
	elseif object.Shape == 'Wedge' then
		local localPoint = object.CFrame:PointToObjectSpace(point)
		local absolutePoint = vector.abs(localPoint)
		if vector.min(absolutePoint, object.HalfSize) == absolutePoint then
			local size = object.HalfSize * 2
			return (localPoint.Y / size.Y - localPoint.Z / size.Z) <= 0
		end
		return false
	end

	return false
end

return Geometry
