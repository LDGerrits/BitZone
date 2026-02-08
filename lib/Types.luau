--!strict

export type ShapeType = 'Block' | 'Ball' | 'Cylinder' | 'Wedge' | 'CornerWedge'

export type BoundingVolume = {
	Position: Vector3,
	CFrame: CFrame,
	HalfSize: Vector3,
	Shape: ShapeType,

	-- Sphere / cylinder specific
	radiusSquared: number?,

	-- Cylinder specific
	start: Vector3?,
	axis: Vector3?,
	axisLength: number?,
}

export type Node = {
	left: Node?,
	right: Node?,
	min: Vector3,
	max: Vector3,
	id: number, -- -1 for internal nodes
}

export type ItemTable = {
	Position: Vector3?,
	WorldPosition: Vector3?,
	CFrame: CFrame?,
	GetPivot: ((self: any) -> CFrame)?,
	[any]: any,
}

export type Item = BasePart | Model | Camera | Attachment | Bone | ItemTable

export type UID = number

export type ItemData = {
	activeGroupMemberships: { [UID]: number },
	memberOfGroups: { [UID]: boolean },
	lastPosition: Vector3,
	strategy: number,
	isDirty: boolean,
}

export type BitZone = {
	SetFrameBudget: (self: BitZone, n: number) -> BitZone,
	SetUpdateRate: (n: number) -> BitZone,
	SetPrecision: (self: BitZone, n: number) -> BitZone,
	DisableSafetyMode: (self: BitZone) -> BitZone,
	newZone: (cframe: CFrame, size: Vector3, shape: Types.ShapeType, associatedPart: BasePart?) -> Zone,
	newZoneFromPart: (part: BasePart) -> Zone,
	newGroup: (priority: number?) -> Group,
	CanItemBeTracked: (self: BitZone, item: any) -> boolean,
	IsItemTracked: (self: BitZone, item: Item) -> boolean,
	GetGroupsForItem: (self: BitZone, item: Item) -> { Group },
	GetGroupsAtItem: (self: BitZone, item: Item) -> { Group },
	GetGroupsAtPoint: (self: BitZone, position: Vector3) -> { Group },
}

export type Zone = {
	BindToGroups: (zone: Zone, ...Group) -> Zone,
	UnbindFromGroups: (zone: Zone, ...Group) -> Zone,
	GetGroups: (zone: Zone) -> { Group },
	Destroy: (zone: Zone) -> (),
	Index: number,
	Part: BasePart?,
}

export type Callback = (Item, Zone, any?) -> ()

export type Group = {
	SetPriority: (self: Group, priority: number) -> Group,
	TrackItem: (self: Group, item: Item, customData: any?) -> Group,
	UntrackItem: (self: Group, item: Item) -> Group,
	TrackLocalPlayer: (self: Group) -> Group,
	TrackPlayers: (self: Group) -> Group,
	IsPlayerInside: (self: Group, player: Player) -> boolean,
	IsLocalPlayerInside: (self: Group) -> boolean,
	OnLocalPlayerEntered: (self: Group, callback: (Zone) -> ()) -> () -> (),
	OnLocalPlayerExited: (self: Group, callback: (Zone) -> ()) -> () -> (),
	OnPlayerEntered: (self: Group, callback: (Player, Zone) -> ()) -> () -> (),
	OnPlayerExited: (self: Group, callback: (Player, Zone) -> ()) -> () -> (),
	OnEntered: (self: Group, callback: Callback) -> () -> (),
	OnExited: (self: Group, callback: Callback) -> () -> (),
	IsItemInside: (self: Group, item: Item) -> boolean,
	IsPointInside: (self: Group, position: Vector3) -> boolean,
	IsItemTracked: (self: Group, item: Item) -> boolean,
	GetTrackedItems: (self: Group) -> { Item },
	GetItemsInside: (self: Group) -> { Item },
	GetZones: (self: Group) -> { Zone },
	Destroy: (self: Group) -> (),
	UID: UID,
}

return nil
