--!native
--!strict

local Geometry = require(script.Parent.Geometry)
local Types = require(script.Parent.Parent.Types)

type ListEntity = {
	id: number,
	mortonCode: number,
}

local LinearBVH = {}
LinearBVH.__index = LinearBVH

local listCache = table.create(2000)
local traversalStack = table.create(64)

local function getSplitPos(list: { ListEntity }, beginIndex: number, endIndex: number): number?
	if (endIndex - beginIndex + 1) < 2 then
		return nil
	end
	if endIndex == beginIndex + 1 then
		return beginIndex + 1
	end

	local first = list[beginIndex].mortonCode
	local last = list[endIndex].mortonCode

	if first == last then
		return (beginIndex + endIndex) // 2
	end

	local xor_val = bit32.bxor(first, last)
	local highest_bit = 31 - bit32.countlz(xor_val)
	local mask = bit32.lshift(1, highest_bit)
	local first_mask = bit32.band(first, mask)

	local left, right = beginIndex, endIndex
	while right - left > 1 do
		local m = (left + right) // 2
		if bit32.band(list[m].mortonCode, mask) == first_mask then
			left = m
		else
			right = m
		end
	end
	return left + 1
end

local function createSubTree(
	list: { ListEntity },
	boundsMin: { Vector3 },
	boundsMax: { Vector3 },
	beginIndex: number,
	endIndex: number
): Types.Node
	if beginIndex == endIndex then
		local id = list[beginIndex].id
		return { min = boundsMin[id], max = boundsMax[id], id = id }
	else
		local mid = getSplitPos(list, beginIndex, endIndex)
		if mid == nil then
			local id = list[beginIndex].id
			return { min = boundsMin[id], max = boundsMax[id], id = id }
		end

		local left = createSubTree(list, boundsMin, boundsMax, beginIndex, mid - 1)
		local right = createSubTree(list, boundsMin, boundsMax, mid, endIndex)
		local min, max = Geometry.unionBounds(left.min, left.max, right.min, right.max)

		return { min = min, max = max, id = -1, left = left, right = right }
	end
end

local HUGE_VECTOR = Vector3.one * math.huge
local NEGATIVE_HUGE_VECTOR = -HUGE_VECTOR

function LinearBVH.build(objects: { Types.BoundingVolume }): Types.Node?
	table.clear(traversalStack)

	local min = HUGE_VECTOR
	local max = NEGATIVE_HUGE_VECTOR
	for _, object in objects do
		local bMin, bMax = Geometry.getObjectBounds(object)
		min = vector.min(min, bMin)
		max = vector.max(max, bMax)
	end

	if min == HUGE_VECTOR then
		return nil
	end

	local padding = vector.max(vector.one, (max - min) * 0.01)
	local sceneMin, sceneMax = min - padding, max + padding

	table.clear(listCache)
	local objMin, objMax = {}, {}

	local count = 0
	for id, object in objects do
		local bMin, bMax = Geometry.getObjectBounds(object)
		objMin[id], objMax[id] = bMin, bMax

		count += 1
		listCache[count] = {
			id = id,
			mortonCode = Geometry.positionToMortonCode(object.position, sceneMin, sceneMax),
		}
	end

	table.sort(listCache, function(a, b)
		return a.mortonCode < b.mortonCode
	end)

	if count > 0 then
		return createSubTree(listCache, objMin, objMax, 1, count)
	end

	return nil
end

function LinearBVH.queryPoint(root: Types.Node?, point: Vector3, callback: (id: number) -> ())
	if not root then
		return
	end

	local stackPtr = 1
	traversalStack[1] = root

	while stackPtr > 0 do
		local node = traversalStack[stackPtr]
		stackPtr -= 1

		local min, max = node.min, node.max
		if
			point.X >= min.X
			and point.X <= max.X
			and point.Y >= min.Y
			and point.Y <= max.Y
			and point.Z >= min.Z
			and point.Z <= max.Z
		then
			if node.id > 0 then
				callback(node.id)
			else
				stackPtr += 1
				traversalStack[stackPtr] = node.left :: Types.Node
				stackPtr += 1
				traversalStack[stackPtr] = node.right :: Types.Node
			end
		end
	end
end

return LinearBVH
