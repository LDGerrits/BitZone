--!strict

local Types = require(script.Parent.Types)

local State = {}

State.nextZoneId = 1
State.nextGroupId = 1
State.nextCollectionId = 1

-- TODO add types
State.collections = {}
State.itemToCollection = {}
State.collectionToGroups = {}

State.objects = {} :: { Types.BoundingVolume }
State.rootNode = nil :: Types.Node?
State.pendingRebuild = false
State.isDirty = false

State.groupTrackingItems = {} :: { [number]: { [Types.Item]: boolean } }
State.groupPriorityMap = {} :: { [number]: number }
State.itemCustomData = {} :: { [Types.Item]: { [number]: any } }
State.groupEnteredCallbacks = {} :: { [number]: { Types.Callback } }
State.groupExitedCallbacks = {} :: { [number]: { Types.Callback } }

State.zoneBoundGroups = {} :: { [number]: { number } }
State.zoneIndexToZoneObj = {} :: { [number]: Types.Zone }
State.groupUIDToGroupObj = {} :: { [number]: Types.Group }

return State
