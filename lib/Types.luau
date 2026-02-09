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

export type BitZone = {
	-- Factories
	newZone: (cframe: CFrame, size: Vector3, shape: ShapeType, associatedPart: BasePart?) -> Zone,
	newZoneFromPart: (part: BasePart) -> Zone,
	newGroup: (priority: number?) -> Group,
	newCollection: (
		{
			UpdateRate: number?,
			Precision: number?,
			SafetyMode: boolean?,
		}?
	) -> Collection,
	playersCollection: (
		{
			UpdateRate: number?,
			Precision: number?,
			SafetyMode: boolean?,
		}?
	) -> Collection,
	localPlayerCollection: (
		{
			UpdateRate: number?,
			Precision: number?,
			SafetyMode: boolean?,
		}?
	) -> Collection,

	-- Global settings
	SetFrameBudget: (self: BitZone, n: number) -> BitZone,

	-- Getters
	GetGroupsAtPoint: (self: BitZone, position: Vector3) -> { Group },
	GetCollectionOfItem: (self: BitZone, item: Item) -> Collection?,
	GetZones: (self: BitZone) -> { Zone },
	GetGroups: (self: BitZone) -> { Group },
	GetCollections: (self: BitZone) -> { Collection },
	GetItems: (self: BitZone) -> { Item },

	-- Queries
	IsItemValidType: (self: BitZone, item: any) -> boolean,
	IsItemInAnyCollection: (self: BitZone, item: Item) -> boolean,
}

export type Zone = {
	-- Lifecycle
	Destroy: (zone: Zone) -> (),

	-- State
	BindToGroups: (zone: Zone, ...Group) -> Zone,
	UnbindFromGroups: (zone: Zone, ...Group) -> Zone,

	-- Utility
	GetGroups: (zone: Zone) -> { Group },

	-- Props
	Index: number,
	Part: BasePart?,
}

export type Callback = (Item, Zone, any?) -> ()

export type Group = {
	-- Lifecycle
	Destroy: (self: Group) -> (),

	-- Settings
	SetPriority: (self: Group, n: number) -> Group,

	-- State
	TrackCollections: (self: Group, ...Collection) -> Group,
	UntrackCollections: (self: Group, ...Collection) -> Group,

	-- Queries
	IsPlayerInside: (self: Group, player: Player) -> boolean,
	IsLocalPlayerInside: (self: Group) -> boolean,
	IsItemInside: (self: Group, item: Item) -> boolean,
	IsPointInside: (self: Group, position: Vector3) -> boolean,

	-- Getters
	GetItemsInside: (self: Group) -> { Item },
	GetItems: (self: Group) -> { Item },
	GetZones: (self: Group) -> { Zone },
	GetCollections: (self: Group) -> { Collection },

	-- Events
	OnEntered: (self: Group, callback: Callback) -> () -> (),
	OnExited: (self: Group, callback: Callback) -> () -> (),
	OnLocalPlayerEntered: (self: Group, callback: (Zone) -> ()) -> () -> (),
	OnLocalPlayerExited: (self: Group, callback: (Zone) -> ()) -> () -> (),
	OnPlayerEntered: (self: Group, callback: (Player, Zone) -> ()) -> () -> (),
	OnPlayerExited: (self: Group, callback: (Player, Zone) -> ()) -> () -> (),

	-- Props
	UID: number,
}

export type Collection = {
	-- Lifecycle
	Destroy: (self: Collection) -> (),

	-- Settings
	SetUpdateRate: (self: Collection, hz: number) -> Collection,
	SetPrecision: (self: Collection, n: number) -> Collection,
	SetSafetyMode: (self: Collection, enabled: boolean) -> Collection,

	-- State
	Add: (self: Collection, item: Item, customData: any?) -> Collection,
	Remove: (self: Collection, item: Item) -> Collection,

	-- Getters
	GetItems: (self: Collection) -> { Item },
	GetGroups: (self: Collection) -> { Group },

	-- Props
	ID: number,
	Items: { Item },
	ItemIndices: { [Item]: number },
	ItemData: { [Item]: ItemData },
	Settings: {
		UpdateRate: number,
		PrecisionSq: number,
		SafetyMode: boolean,
	},
	LastProcessedIndex: number,
}

export type ItemTable = {
	Position: Vector3?,
	WorldPosition: Vector3?,
	CFrame: CFrame?,
	GetPivot: ((self: any) -> CFrame)?,
	[any]: any,
}

export type Item = BasePart | Model | Camera | Attachment | Bone | ItemTable

export type ItemData = {
	activeGroupMemberships: { [number]: number },
	lastPosition: Vector3,
	strategy: number,
	isDirty: boolean,
}

return nil
