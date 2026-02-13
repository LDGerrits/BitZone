--!strict

--[=[
	@type ShapeType "Block" | "Ball" | "Cylinder" | "Wedge" | "CornerWedge"
	@within QuickZone

	Represents the geometric volume of a Zone.
]=]
export type ShapeType = 'Block' | 'Ball' | 'Cylinder' | 'Wedge' | 'CornerWedge'

export type BoundingVolume = {
	position: Vector3,
	cframe: CFrame,
	halfSize: Vector3,
	type: ShapeType,

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
	Zone: (cframe: CFrame, size: Vector3, shape: ShapeType, associatedPart: BasePart?, isDynamic: boolean?) -> Zone,
	ZoneFromPart: (part: BasePart, isDynamic: boolean?) -> Zone,
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
	getZonesAtPoint: (self: QuickZone, position: Vector3) -> { Zone },
	getObserversAtPoint: (self: QuickZone, position: Vector3) -> { Observer },
	getGroupOfEntity: (self: QuickZone, entity: Entity) -> Group?,
	getZones: (self: QuickZone) -> { Zone },
	getObservers: (self: QuickZone) -> { Observer },
	getGroups: (self: QuickZone) -> { Group },
	getEntities: (self: QuickZone) -> { Entity },

	-- Helpers
	visualize: (self: QuickZone, enabled: boolean) -> QuickZone,
}

export type Zone = {
	-- Lifecycle
	destroy: (self: Zone) -> (),

	-- State
	attach: (self: Zone, ...Observer) -> Zone,
	detach: (self: Zone, ...Observer) -> Zone,
	update: (self: Zone, newCFrame: CFrame?, newSize: Vector3?) -> Zone,

	-- Getters
	getId: (self: Zone) -> number,
	getPart: (self: Zone) -> BasePart?,
	getShapeType: (self: Zone) -> ShapeType,
	getObservers: (self: Zone) -> { Observer },
	isDynamic: (self: Zone) -> boolean,

	-- Utility
	isPointInside: (self: Zone, point: Vector3) -> boolean,
}

export type InternalZone = Zone & {
	id: number,
	part: BasePart?,
	dynamic: boolean,
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
	setEnabled: (self: Observer, enabled: boolean) -> Observer,

	-- Queries
	isEnabled: (self: Observer) -> boolean,
	isPlayerInside: (self: Observer, player: Player) -> boolean,
	isLocalPlayerInside: (self: Observer) -> boolean,
	isEntityInside: (self: Observer, entity: Entity) -> boolean,
	isPointInside: (self: Observer, position: Vector3) -> boolean,
	getEntitiesInside: (self: Observer) -> { Entity },

	-- Getters
	getId: (self: Observer) -> number,
	getPriority: (self: Observer) -> number,
	getZones: (self: Observer) -> { Zone },
	getGroups: (self: Observer) -> { Group },

	-- Events
	onEntered: (self: Observer, callback: Callback) -> () -> (),
	onExited: (self: Observer, callback: Callback) -> () -> (),
	onLocalPlayerEntered: (self: Observer, callback: (Zone) -> ()) -> () -> (),
	onLocalPlayerExited: (self: Observer, callback: (Zone) -> ()) -> () -> (),
	onPlayerEntered: (self: Observer, callback: (Player, Zone) -> ()) -> () -> (),
	onPlayerExited: (self: Observer, callback: (Player, Zone) -> ()) -> () -> (),
}

export type InternalObserver = Observer & {
	id: number,
}

export type Group = {
	-- Lifecycle
	destroy: (self: Group) -> (),

	-- Config
	setConfig: (
		self: Group,
		{
			updateRate: number?,
			precision: number?,
			safety: boolean?,
		}
	) -> Group,

	-- State
	add: (self: Group, entity: Entity, metadata: any?) -> Group,
	remove: (self: Group, ...Entity) -> Group,

	-- Getters
	getId: (self: Group) -> number,
	getEntities: (self: Group) -> { Entity },
	getObservers: (self: Group) -> { Observer },
	getConfig: (self: Group) -> {
		updateRate: number,
		precision: number,
		safety: boolean,
	},

	-- Helpers
	contains: (self: Group, entity: Entity) -> boolean,
}

export type InternalGroup = Group & {
	id: number,
	entities: { Entity },
	entityIndices: { [Entity]: number },
	entityData: { [Entity]: EntityData },
	config: {
		updateRate: number,
		precisionSq: number,
		safety: boolean,
	},
}

--[=[
	@type Entity BasePart | Model | Camera | Attachment | Bone | EntityTable
	@within QuickZone

	An Entity is any object that can be tracked within a Group. Supports native 
	Roblox Instances and custom "duck-typed" tables.
]=]
export type Entity = BasePart | Model | Camera | Attachment | Bone | EntityTable

--[=[
	@interface EntityTable
	@within QuickZone
	.Position Vector3?
	.WorldPosition Vector3?
	.CFrame CFrame?
	.GetPivot (() -> CFrame)?

	A custom table that mimics the spatial properties of a Roblox Instance. 
	QuickZone will automatically detect which property to use to track this entity.
]=]
export type EntityTable = {
	Position: Vector3?,
	WorldPosition: Vector3?,
	CFrame: CFrame?,
	GetPivot: ((self: any) -> CFrame)?,
	[any]: any,
}

export type EntityData = {
	activeObserverMemberships: { [number]: number },
	lastPosition: Vector3,
	strategy: number,
	isDirty: boolean,
}

return nil
