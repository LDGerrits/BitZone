--!strict

local Types = require(script.Parent.Types)

local State = {}

State.NextZoneId = 1
State.NextObserverId = 1
State.NextGroupId = 1

State.Groups = {} :: { [number]: Types.Group }
State.EntityToGroup = {} :: { [Types.Entity]: number }
State.GroupToObservers = {} :: { [number]: { [number]: boolean } }

State.Objects = {} :: { Types.BoundingVolume }
State.RootNode = nil :: Types.Node?
State.PendingRebuild = false
State.IsDirty = false

State.ObserverTrackingEntities = {} :: { [number]: { [Types.Entity]: boolean } }
State.ObserverPriorityMap = {} :: { [number]: number }
State.EntityCustomData = {} :: { [Types.Entity]: { [number]: any } }
State.ObserverEnteredCallbacks = {} :: { [number]: { Types.Callback } }
State.ObserverExitedCallbacks = {} :: { [number]: { Types.Callback } }

State.ZoneBoundObservers = {} :: { [number]: { number } }
State.ZoneIdToZoneObj = {} :: { [number]: Types.Zone }
State.ObserverIdToObserverObj = {} :: { [number]: Types.Observer }

return State
