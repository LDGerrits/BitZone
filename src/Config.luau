--!strict

local Config = {}

-- Static enums used to determine how to read an entity's position
Config.Strategy = {
	POS = 1,
	PRIM = 2,
	WORLD = 3,
	CFRAME = 4,
	PIVOT = 5,
}

-- Initial values of the scheduler
Config.Scheduler = {
	-- Maximum execution time (in seconds) per frame
	-- 0.001 = 1ms (approx 6% of a frame at 60 FPS)
	FrameBudget = 1 / 1000,

	-- Update frequency (Hz).
	-- 30 means every entity is checked ~30 times per second
	updateRate = 30,

	-- Minimum positional change (in studs) required to trigger a spatial query
	-- Entities moving less than this distance are considered stationary
	precision = 0.1,

	-- If true, callbacks are fired via task.spawn (safe but slower)
	-- If false, callbacks fire immediately (risky if not handled appropriately)
	safety = true,
}

return Config
