--!strict

local Types = require(script.Parent.Types)

local State = {}

State.nextZoneId = 1
State.nextObserverId = 1
State.nextGroupId = 1

State.groups = {} :: { [number]: Types.Group }
State.entityToGroup = {} :: { [Types.Entity]: number }
State.groupToObservers = {} :: { [number]: { [number]: boolean } }

State.objects = {} :: { Types.BoundingVolume }
State.rootNode = nil :: Types.Node?
State.pendingRebuild = false
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
