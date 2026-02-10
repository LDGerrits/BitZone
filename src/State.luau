--!strict

local Types = require(script.Parent.Types)

local State = {}

State.nextZoneId = 1
State.nextObserverId = 1
State.nextGroupId = 1

State.groups = {} :: { [number]: Types.Group }
State.entityToGroup = {} :: { [Types.Entity]: number }
State.groupToObservers = {} :: { [number]: { [number]: boolean } }

State.staticShapes = {} :: { Types.BoundingVolume }
State.dynamicShapes = {} :: { Types.BoundingVolume }
State.staticRootNode = nil :: Types.Node?
State.dynamicRootNode = nil :: Types.Node?
State.pendingStaticRebuild = false
State.pendingDynamicRebuild = false
State.isDirty = false

State.observerTrackingEntities = {} :: { [number]: { [Types.Entity]: boolean } }
State.ObserverPriorityMap = {} :: { [number]: number }
State.entityCustomData = {} :: { [Types.Entity]: { [number]: any } }
State.observerEnteredCallbacks = {} :: { [number]: { Types.Callback } }
State.observerExitedCallbacks = {} :: { [number]: { Types.Callback } }

State.zoneAttachedObservers = {} :: { [number]: { number } }
State.zoneIdToZoneObj = {} :: { [number]: Types.Zone }
State.observerIdToObserverObj = {} :: { [number]: Types.Observer }

return State
