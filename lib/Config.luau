--!strict

local Config = {}

-- Static enums used to determine how to read an item's position
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

	-- Target update frequency (Hz).
	-- 30 means every item is checked ~30 times per second
	UpdateRate = 30,

	-- Minimum positional change (in studs) required to trigger a spatial query
	-- Items moving less than this distance are considered stationary
	Precision = 0.1,

	-- If true, callbacks are fired via task.spawn (safe but slower)
	-- If false, callbacks fire immediately (risky if not handled appropriately)
	SafetyMode = true,
}

return Config
