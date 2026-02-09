--!strict

export type ShapeType = 'Block' | 'Ball' | 'Cylinder' | 'Wedge' | 'CornerWedge'

export type BoundingVolume = {
	Position: Vector3,
	CFrame: CFrame,
	HalfSize: Vector3,
	Shape: ShapeType,

	-- Sphere / cylinder specific
	RadiusSq: number?,

	-- Cylinder specific
	Start: Vector3?,
	Axis: Vector3?,
	AxisLength: number?,
}

export type Node = {
	Left: Node?,
	Right: Node?,
	Min: Vector3,
	Max: Vector3,
	Id: number, -- -1 for internal nodes
}

export type BitZone = {
	-- Factories
	newZone: (cframe: CFrame, size: Vector3, shape: ShapeType, associatedPart: BasePart?) -> Zone,
	newZoneFromPart: (part: BasePart) -> Zone,
	newObserver: (priority: number?) -> Observer,
	newGroup: ({
		UpdateRate: number?,
		Precision: number?,
		SafetyMode: boolean?,
	}?) -> Group,
	playersGroup: ({
		UpdateRate: number?,
		Precision: number?,
		SafetyMode: boolean?,
	}?) -> Group,
	localPlayerGroup: ({
		UpdateRate: number?,
		Precision: number?,
		SafetyMode: boolean?,
	}?) -> Group,

	-- Global config
	SetFrameBudget: (self: BitZone, n: number) -> BitZone,

	-- Getters
	GetObserversAtPoint: (self: BitZone, position: Vector3) -> { Observer },
	GetGroupOfEntity: (self: BitZone, entity: Entity) -> Group?,
	GetZones: (self: BitZone) -> { Zone },
	GetObservers: (self: BitZone) -> { Observer },
	GetGroups: (self: BitZone) -> { Group },
	GetEntities: (self: BitZone) -> { Entity },

	-- Queries
	IsEntityValidType: (self: BitZone, entity: any) -> boolean,
	IsEntityInAnyGroup: (self: BitZone, entity: Entity) -> boolean,
}

export type Zone = {
	-- Lifecycle
	Destroy: (zone: Zone) -> (),

	-- State
	BindToObservers: (zone: Zone, ...Observer) -> Zone,
	UnbindFromObservers: (zone: Zone, ...Observer) -> Zone,

	-- Utility
	GetObservers: (zone: Zone) -> { Observer },

	-- Props
	Id: number,
	Part: BasePart?,
}

export type Callback = (Entity, Zone, any?) -> ()

export type Observer = {
	-- Lifecycle
	Destroy: (self: Observer) -> (),

	-- Config
	SetPriority: (self: Observer, n: number) -> Observer,

	-- State
	Track: (self: Observer, Group) -> Observer,
	Untrack: (self: Observer, Group) -> Observer,

	-- Queries
	IsPlayerInside: (self: Observer, player: Player) -> boolean,
	IsLocalPlayerInside: (self: Observer) -> boolean,
	IsEntityInside: (self: Observer, entity: Entity) -> boolean,
	IsPointInside: (self: Observer, position: Vector3) -> boolean,

	-- Getters
	GetEntitiesInside: (self: Observer) -> { Entity },
	GetEntities: (self: Observer) -> { Entity },
	GetZones: (self: Observer) -> { Zone },
	GetGroups: (self: Observer) -> { Group },

	-- Events
	OnEntered: (self: Observer, callback: Callback) -> () -> (),
	OnExited: (self: Observer, callback: Callback) -> () -> (),
	OnLocalPlayerEntered: (self: Observer, callback: (Zone) -> ()) -> () -> (),
	OnLocalPlayerExited: (self: Observer, callback: (Zone) -> ()) -> () -> (),
	OnPlayerEntered: (self: Observer, callback: (Player, Zone) -> ()) -> () -> (),
	OnPlayerExited: (self: Observer, callback: (Player, Zone) -> ()) -> () -> (),

	-- Props
	Id: number,
}

export type Group = {
	-- Lifecycle
	Destroy: (self: Group) -> (),

	-- Config
	SetUpdateRate: (self: Group, hz: number) -> Group,
	SetPrecision: (self: Group, n: number) -> Group,
	SetSafetyMode: (self: Group, enabled: boolean) -> Group,
	SetConfig: (
		self: Group,
		{
			UpdateRate: number?,
			Precision: number?,
			SafetyMode: boolean?,
		}?
	) -> Group,

	-- State
	Add: (self: Group, entity: Entity, customData: any?) -> Group,
	Remove: (self: Group, entity: Entity) -> Group,

	-- Getters
	GetEntities: (self: Group) -> { Entity },
	GetObservers: (self: Group) -> { Observer },
	GetConfig: (self: Group) -> {
		UpdateRate: number,
		Precision: number,
		SafetyMode: boolean,
	},

	-- Props
	Id: number,
	_entities: { Entity },
	_entityIndices: { [Entity]: number },
	_entityData: { [Entity]: EntityData },
	_config: {
		UpdateRate: number,
		PrecisionSq: number,
		SafetyMode: boolean,
	},
	_lastProcessedIndex: number,
}

export type EntityTable = {
	Position: Vector3?,
	WorldPosition: Vector3?,
	CFrame: CFrame?,
	GetPivot: ((self: any) -> CFrame)?,
	[any]: any,
}

export type Entity = BasePart | Model | Camera | Attachment | Bone | EntityTable

export type EntityData = {
	ActiveObserverMemberships: { [number]: number },
	LastPosition: Vector3,
	Strategy: number,
	IsDirty: boolean,
}

return nil
