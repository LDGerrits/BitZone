--!strict

--[=[
	@type ShapeType "Block" | "Ball" | "Cylinder" | "Wedge" | "CornerWedge"
	@within QuickZone
	The geometric shape of a Zone.
]=]
export type ShapeType = 'Block' | 'Ball' | 'Cylinder' | 'Wedge' | 'CornerWedge'

--[=[
	@interface EntityTable
	@within QuickZone
	.Position Vector3?
	.WorldPosition Vector3?
	.CFrame CFrame?
	.Transform: CFrame?
	.GetPivot ((any) -> CFrame)?
	A custom table that mimics the spatial properties of a Roblox Instance.
]=]
export type EntityTable = {
	Position: Vector3?,
	WorldPosition: Vector3?,
	CFrame: CFrame?,
	Transform: CFrame?,
	GetPivot: ((self: any) -> CFrame)?,
}

--[=[
	@type Entity Player | BasePart | Model | Camera | Attachment | Bone | EntityTable
	@within QuickZone
]=]
export type Entity = Player | BasePart | Model | Camera | Attachment | Bone | EntityTable

export type BoundingVolume = {
	position: Vector3,
	cframe: CFrame,
	halfSize: Vector3,
	type: ShapeType,
	radiusSq: number?,
	start: Vector3?,
	axis: Vector3?,
	axisLength: number?,
}

export type Node = {
	min: Vector3,
	max: Vector3,
	id: number,
	skipIndex: number,
}

export type Tree = {
	nodes: { Node },
	count: number,
}

export type EntityData = {
	activeObserverMemberships: { [number]: number },
	lastPosition: Vector3,
	strategy: number,
	precisionSq: number,
	updateRate: number,
	bucketIndex: number,
	staticVersion: number,
	dynamicVersion: number,
	logicVersion: number,
	needsStatic: boolean,
	needsDynamic: boolean,
}

export type Group<T = any> = {
	add: (self: Group<T>, entity: T) -> Group<T>,
	addBulk: (self: Group<T>, entities: { T }) -> Group<T>,
	remove: (self: Group<T>, entity: T) -> Group<T>,
	removeBulk: (self: Group<T>, entities: { T }) -> Group<T>,
	clear: (self: Group<T>) -> Group<T>,

	setAutoClean: (self: Group<T>, enabled: boolean) -> Group<T>,
	getId: (self: Group<T>) -> number,
	getEntities: (self: Group<T>) -> { T },
	contains: (self: Group<T>, entity: T) -> boolean,
	iterEntities: (self: Group<T>) -> () -> T?,
	onDestroy: (self: Group<T>, callback: () -> ()) -> () -> (),
	destroy: (self: Group<T>) -> (),
}

export type InternalGroup<T = any> = Group<T> & {
	_add: (self: Group<T>, entity: T) -> Group<T>,
	_addBulk: (self: Group<T>, entities: { T }) -> Group<T>,
	_remove: (self: Group<T>, entity: T) -> Group<T>,
	_removeBulk: (self: Group<T>, entities: { T }) -> Group<T>,
	_clear: (self: Group<T>) -> Group<T>,
	id: number,
	entities: { T },
	entityIndices: { [any]: number },
	isManaged: boolean?,
	autoClean: boolean,
	onDestroyCallbacks: { () -> () }?,
}

export type GroupClass = {
	new: <T>(config: {
		entities: { T }?,
		autoClean: boolean?,
	}?) -> Group<T>,
	fromTag: (tag: string) -> Group<Entity>,
	players: () -> Group<Player>,
	localPlayer: () -> Group<Player>,
}

export type Zone = {
	sync: (self: Zone) -> Zone,
	setReference: (self: Zone, reference: (Attachment | BasePart | Bone)?) -> Zone,
	setAutoSync: (self: Zone, autoSync: boolean) -> Zone,
	setDynamic: (self: Zone, dynamic: boolean) -> Zone,
	setCFrame: (self: Zone, cf: CFrame) -> Zone,
	setPosition: (self: Zone, pos: Vector3) -> Zone,
	setSize: (self: Zone, size: Vector3) -> Zone,
	setShape: (self: Zone, shape: ShapeType) -> Zone,
	setMetadata: (self: Zone, metadata: any?) -> Zone,

	getMetadata: (self: Zone) -> any?,
	getId: (self: Zone) -> number,
	getReference: (self: Zone) -> (Attachment | BasePart | Bone)?,
	getPosition: (self: Zone) -> Vector3,
	getCFrame: (self: Zone) -> CFrame,
	getSize: (self: Zone) -> Vector3,
	getShape: (self: Zone) -> ShapeType,

	isDynamic: (self: Zone) -> boolean,
	isPointInside: (self: Zone, point: Vector3) -> boolean,

	onDestroy: (self: Zone, callback: () -> ()) -> () -> (),
	destroy: (self: Zone) -> (),
}

export type InternalZone = Zone & {
	attach: (self: Zone, observer: any) -> Zone,
	detach: (self: Zone, observer: any) -> Zone,

	id: number,
	reference: (Attachment | BasePart | Bone)?,
	dynamic: boolean,
	metadata: any?,
	autoSync: boolean,
	syncConnections: { RBXScriptConnection }?,
	onDestroyCallbacks: { () -> () }?,
}

export type Zones = {
	sync: (self: Zones) -> Zones,
	setAutoSync: (self: Zones, autoSync: boolean) -> Zones,
	setDynamic: (self: Zones, dynamic: boolean) -> Zones,
	getZones: (self: Zones) -> { Zone },
	getMetadata: (self: Zones) -> any?,
	isDynamic: (self: Zones) -> boolean,
	isPointInside: (self: Zones, point: Vector3) -> boolean,
	setMetadata: (self: Zones, metadata: any?) -> Zones,
	contains: (self: Zones, zone: Zone) -> boolean,
	iterZones: (self: Zones) -> () -> Zone?,
	getReferences: (self: Zones) -> { Attachment | BasePart | Bone },
	iterReferences: (self: Zones) -> () -> ((Attachment | BasePart | Bone)?, Zone?),

	onDestroy: (self: Zones, callback: () -> ()) -> () -> (),
	destroy: (self: Zones) -> (),
}

export type InternalZones = Zones & {
	attach: (self: Zones, observer: any) -> Zones,
	detach: (self: Zones, observer: any) -> Zones,

	autoSync: boolean?,
	dynamic: boolean,
	metadata: any?,
	zones: { [any]: boolean },
	observers: { [any]: boolean },
	onDestroyCallbacks: { () -> () }?,
	onDestroyObserverCleanups: { [any]: () -> () },
	onDestroyZoneCleanups: { [any]: () -> () },
	add: (self: InternalZones, zone: Zone) -> (),
	remove: (self: InternalZones, zone: Zone) -> (),
}

export type ZoneClass = {
	new: (
		config: {
			cframe: CFrame,
			size: Vector3,
			shape: ShapeType?,
			reference: (Attachment | BasePart | Bone)?,
			isDynamic: boolean?,
			metadata: any?,
			autoSync: boolean?,
		}
	) -> Zone,
	fromPart: (part: BasePart, config: { isDynamic: boolean?, metadata: any?, autoSync: boolean? }?) -> Zone,
	fromParts: (
		parts: { BasePart },
		config: { isDynamic: boolean?, metadata: any?, autoSync: boolean? }?
	) -> Zones,
	fromTag: (tag: string, config: { isDynamic: boolean?, metadata: any?, autoSync: boolean? }?) -> Zones,
	fromDescendants: (
		parent: Instance,
		config: { isDynamic: boolean?, metadata: any?, autoSync: boolean? }?
	) -> Zones,
	fromChildren: (
		parent: Instance,
		config: { isDynamic: boolean?, metadata: any?, autoSync: boolean? }?
	) -> Zones,
}

export type Observer<T = any> = {
	subscribe: (self: Observer<T>, group: Group<T>) -> Observer<T>,
	unsubscribe: (self: Observer<T>, group: Group<T>) -> Observer<T>,
	attach: (self: Observer<T>, zone: Zone | Zones) -> Observer<T>,
	detach: (self: Observer<T>, zone: Zone | Zones) -> Observer<T>,

	setPriority: (self: Observer<T>, n: number) -> Observer<T>,
	setUpdateRate: (self: Observer<T>, hz: number) -> Observer<T>,
	setPrecision: (self: Observer<T>, n: number) -> Observer<T>,
	setEnabled: (self: Observer<T>, enabled: boolean) -> Observer<T>,
	setSafety: (self: Observer<T>, enabled: boolean) -> Observer<T>,

	isEnabled: (self: Observer<T>) -> boolean,
	isSafe: (self: Observer<T>) -> boolean,
	isPointInside: (self: Observer<T>, position: Vector3) -> boolean,

	getId: (self: Observer<T>) -> number,
	getPriority: (self: Observer<T>) -> number,
	getUpdateRate: (self: Observer<T>) -> number,
	getPrecision: (self: Observer<T>) -> number,
	getZones: (self: Observer<T>) -> { Zone },
	getGroups: (self: Observer<T>) -> { Group<T> },
	getEntitiesInside: (self: Observer<T>) -> { T },
	getPlayersInside: (self: Observer<T>) -> { Player },
	getZoneOfEntity: (self: Observer<T>, entity: T) -> Zone?,
	getZoneOfPlayer: (self: Observer<T>, player: Player) -> Zone?,
	getEntitiesInZone: (self: Observer<T>, zone: Zone) -> { T },
	getPlayersInZone: (self: Observer<T>, zone: Zone) -> { Player },

	iterZones: (self: Observer<T>) -> () -> Zone?,
	iterGroups: (self: Observer<T>) -> () -> Group<T>?,
	iterEntitiesInside: (self: Observer<T>) -> () -> (T?, Zone?),
	iterPlayersInside: (self: Observer<T>) -> () -> (Player?, Zone?),
	iterEntitiesInZone: (self: Observer<T>, zone: Zone) -> () -> T?,
	iterPlayersInZone: (self: Observer<T>, zone: Zone) -> () -> Player?,

	observe: (self: Observer<T>, callback: (T, Zone) -> (() -> ())?) -> () -> (),
	observePlayer: (self: Observer<T>, callback: (Player, Zone) -> (() -> ())?) -> () -> (),
	observeLocalPlayer: (self: Observer<T>, callback: (Zone) -> (() -> ())?) -> () -> (),
	observeGroup: (self: Observer<T>, callback: (Group<T>, Zone) -> (() -> ())?) -> () -> (),
	onEnter: (self: Observer<T>, callback: (T, Zone) -> ()) -> () -> (),
	onExit: (self: Observer<T>, callback: (T, Zone) -> ()) -> () -> (),
	onPlayerEnter: (self: Observer<T>, callback: (Player, Zone) -> ()) -> () -> (),
	onPlayerExit: (self: Observer<T>, callback: (Player, Zone) -> ()) -> () -> (),
	onLocalPlayerEnter: (self: Observer<T>, callback: (Zone) -> ()) -> () -> (),
	onLocalPlayerExit: (self: Observer<T>, callback: (Zone) -> ()) -> () -> (),
	onGroupEnter: (self: Observer<T>, callback: (Group<T>, Zone) -> ()) -> () -> (),
	onGroupExit: (self: Observer<T>, callback: (Group<T>, Zone) -> ()) -> () -> (),
	onTransition: (self: Observer<T>, callback: (T, Zone) -> ()) -> () -> (),
	onPlayerTransition: (self: Observer<T>, callback: (Player, Zone) -> ()) -> () -> (),
	onLocalPlayerTransition: (self: Observer<T>, callback: (Zone) -> ()) -> () -> (),

	onDestroy: (self: Observer<T>, callback: () -> ()) -> () -> (),
	destroy: (self: Observer<T>) -> (),
}

export type ObserverClass = {
	new: <T>(
		config: {
			groups: { Group<T> }?,
			zones: { Zone | Zones }?,
			priority: number?,
			updateRate: number?,
			precision: number?,
			enabled: boolean?,
			safety: boolean?,
		}?
	) -> Observer<T>,
}

export type InternalObserver<T = any> = Observer<T> & {
	id: number,
	onDestroyCallbacks: { () -> () }?,
}

export type QuickZone = {
	Zone: ZoneClass,
	Observer: ObserverClass,
	Group: GroupClass,

	configure: (
		self: QuickZone,
		config: { enabled: boolean?, autoSyncRate: number?, frameBudget: number? }
	) -> QuickZone,
	setEnabled: (self: QuickZone, enabled: boolean) -> QuickZone,
	setAutoSyncRate: (self: QuickZone, hz: number) -> QuickZone,
	rebuild: (self: QuickZone) -> QuickZone,
	update: (self: QuickZone, dt: number) -> QuickZone,
	setFrameBudget: (self: QuickZone, ms: number) -> QuickZone,
	setReference: (self: QuickZone, entity: Entity, reference: any?) -> QuickZone,
	visualize: (self: QuickZone, enabled: boolean) -> QuickZone,
	removeEntity: (self: QuickZone, entity: any) -> QuickZone,

	getEntityOfReference: (self: QuickZone, reference: any) -> Entity?,
	getReferenceOfEntity: (self: QuickZone, entity: Entity) -> any,
	getZones: (self: QuickZone) -> { Zone },
	getObservers: (self: QuickZone) -> { Observer<any> },
	getGroups: (self: QuickZone) -> { Group<any> },
	getEntities: (self: QuickZone) -> { any },
	iterZones: (self: QuickZone) -> () -> Zone?,
	iterObservers: (self: QuickZone) -> () -> Observer<any>?,
	iterGroups: (self: QuickZone) -> () -> Group<any>?,
	iterEntities: (self: QuickZone) -> () -> any?,
	getZonesAtPoint: (self: QuickZone, position: Vector3) -> { Zone },
	iterZonesAtPoint: (self: QuickZone, position: Vector3) -> () -> Zone?,
	getZonesOfEntity: (self: QuickZone, entity: any) -> { Zone },
	iterZonesOfEntity: (self: QuickZone, entity: any) -> () -> Zone?,
	getGroupsOfEntity: (self: QuickZone, entity: any) -> { Group<any> },
	iterGroupsOfEntity: (self: QuickZone, entity: any) -> () -> Group<any>?,
}

return nil
