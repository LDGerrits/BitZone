--!strict

export type ShapeType = 'Block' | 'Ball' | 'Cylinder' | 'Wedge' | 'CornerWedge'

export type BoundingVolume = {
	position: Vector3,
	cframe: CFrame,
	halfSize: Vector3,
	shape: ShapeType,

	-- Sphere / cylinder specific
	radiusSq: number?,

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

export type QuickZone = {
	-- Factories
	Zone: (cframe: CFrame, size: Vector3, shape: ShapeType, associatedPart: BasePart?) -> Zone,
	ZoneFromPart: (part: BasePart) -> Zone,
	Observer: (priority: number?) -> Observer,
	Group: ({
		updateRate: number?,
		precision: number?,
		safety: boolean?,
	}?) -> Group,
	PlayerGroup: ({
		updateRate: number?,
		precision: number?,
		safety: boolean?,
	}?) -> Group,
	LocalPlayerGroup: ({
		updateRate: number?,
		precision: number?,
		safety: boolean?,
	}?) -> Group,

	-- Global config
	setFrameBudget: (self: QuickZone, n: number) -> QuickZone,

	-- Getters
	getObserversAtPoint: (self: QuickZone, position: Vector3) -> { Observer },
	getGroupOfEntity: (self: QuickZone, entity: Entity) -> Group?,
	getZones: (self: QuickZone) -> { Zone },
	getObservers: (self: QuickZone) -> { Observer },
	getGroups: (self: QuickZone) -> { Group },
	getEntities: (self: QuickZone) -> { Entity },

	-- Queries
	isEntityValidType: (self: QuickZone, entity: any) -> boolean,
	isEntityInAnyGroup: (self: QuickZone, entity: Entity) -> boolean,
}

export type Zone = {
	-- Lifecycle
	destroy: (zone: Zone) -> (),

	-- State
	attach: (zone: Zone, ...Observer) -> Zone,
	detach: (zone: Zone, ...Observer) -> Zone,

	-- Utility
	getObservers: (zone: Zone) -> { Observer },

	-- Props
	id: number,
	part: BasePart?,
}

export type Callback = (Entity, Zone, any?) -> ()

export type Observer = {
	-- Lifecycle
	destroy: (self: Observer) -> (),

	-- Config
	setPriority: (self: Observer, n: number) -> Observer,

	-- State
	subscribe: (self: Observer, ...Group) -> Observer,
	unsubscribe: (self: Observer, ...Group) -> Observer,

	-- Queries
	isPlayerInside: (self: Observer, player: Player) -> boolean,
	isLocalPlayerInside: (self: Observer) -> boolean,
	isEntityInside: (self: Observer, entity: Entity) -> boolean,
	isPointInside: (self: Observer, position: Vector3) -> boolean,

	-- Getters
	getEntitiesInside: (self: Observer) -> { Entity },
	getEntities: (self: Observer) -> { Entity },
	getZones: (self: Observer) -> { Zone },
	getGroups: (self: Observer) -> { Group },

	-- Events
	onEntered: (self: Observer, callback: Callback) -> () -> (),
	onExited: (self: Observer, callback: Callback) -> () -> (),
	onLocalPlayerEntered: (self: Observer, callback: (Zone) -> ()) -> () -> (),
	onLocalPlayerExited: (self: Observer, callback: (Zone) -> ()) -> () -> (),
	onPlayerEntered: (self: Observer, callback: (Player, Zone) -> ()) -> () -> (),
	onPlayerExited: (self: Observer, callback: (Player, Zone) -> ()) -> () -> (),

	-- Props
	id: number,
}

export type Group = {
	-- Lifecycle
	destroy: (self: Group) -> (),

	-- Config
	setUpdateRate: (self: Group, hz: number) -> Group,
	setPrecision: (self: Group, n: number) -> Group,
	setSafetyMode: (self: Group, enabled: boolean) -> Group,
	setConfig: (
		self: Group,
		{
			updateRate: number?,
			precision: number?,
			safety: boolean?,
		}?
	) -> Group,

	-- State
	add: (self: Group, entity: Entity, customData: any?) -> Group,
	remove: (self: Group, ...Entity) -> Group,

	-- Getters
	getEntities: (self: Group) -> { Entity },
	getObservers: (self: Group) -> { Observer },
	getConfig: (self: Group) -> {
		updateRate: number,
		precision: number,
		safety: boolean,
	},

	-- Props
	id: number,
	_entities: { Entity },
	_entityIndices: { [Entity]: number },
	_entityData: { [Entity]: EntityData },
	_config: {
		updateRate: number,
		PrecisionSq: number,
		safety: boolean,
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
	activeObserverMemberships: { [number]: number },
	lastPosition: Vector3,
	strategy: number,
	isDirty: boolean,
}

return nil
