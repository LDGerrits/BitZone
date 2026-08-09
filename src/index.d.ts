export type ShapeType = "Block" | "Ball" | "Cylinder" | "Wedge" | "CornerWedge"

export interface EntityTable {
	Position?: Vector3
	WorldPosition?: Vector3
	CFrame?: CFrame
	Transform?: CFrame
	GetPivot?: (self: any) => CFrame
}

export type Entity = Player | BasePart | Model | Camera | Attachment | Bone | EntityTable

export interface Zone {
	setAutoSync(autoSync: boolean): Zone
	setReference(reference: BasePart | Attachment | Bone | undefined): Zone
	sync(): Zone
	setDynamic(isDynamic: boolean): Zone
	setCFrame(cf: CFrame): Zone
	setPosition(pos: Vector3): Zone
	setSize(size: Vector3): Zone
	setShape(shape: ShapeType): Zone
	setMetadata(metadata: any): Zone
	getMetadata(): any
	getId(): number
	getReference(): BasePart | Attachment | Bone | undefined
	getPosition(): Vector3
	getCFrame(): CFrame
	getSize(): Vector3
	getShape(): ShapeType
	isPointInside(point: Vector3): boolean
	isDynamic(): boolean
	onDestroy(callback: () => void): () => void
	destroy(): void
}

export interface Zones {
	sync(): Zones
	getZones(): Zone[]
	isDynamic(): boolean
	isPointInside(point: Vector3): boolean
	setAutoSync(autoSync: boolean): Zones
	setDynamic(isDynamic: boolean): Zones
	setMetadata(metadata: any): Zones
	getMetadata(): any
	contains(zone: Zone): boolean
	iterZones(): IterableFunction<Zone>
	getReferences(): (BasePart | Attachment | Bone)[]
	iterReferences(): IterableFunction<LuaTuple<[BasePart | Attachment | Bone, Zone]>>
	onDestroy(callback: () => void): () => void
	destroy(): void
}

export interface ObserverConfig {
	groups?: Group[]
	zones?: (Zone | Zones)[]
	priority?: number
	updateRate?: number
	precision?: number
	enabled?: boolean
	safety?: boolean
}

export interface Observer {
	subscribe(group: Group): Observer
	unsubscribe(group: Group): Observer
	attach(zone: Zone | Zones): Observer
	detach(zone: Zone | Zones): Observer
	observe(callback: (entity: any, zone: Zone) => (() => void) | undefined): () => void
	onEnter(callback: (entity: any, zone: Zone) => void): () => void
	onExit(callback: (entity: any, zone: Zone) => void): () => void
	observePlayer(callback: (player: Player, zone: Zone) => (() => void) | undefined): () => void
	onPlayerEnter(callback: (player: Player, zone: Zone) => void): () => void
	onPlayerExit(callback: (player: Player, zone: Zone) => void): () => void
	observeLocalPlayer(callback: (zone: Zone) => (() => void) | undefined): () => void
	onLocalPlayerEnter(callback: (zone: Zone) => void): () => void
	onLocalPlayerExit(callback: (zone: Zone) => void): () => void
	observeGroup(callback: (group: Group, zone: Zone) => (() => void) | undefined): () => void
	onGroupEnter(callback: (group: Group, zone: Zone) => void): () => void
	onGroupExit(callback: (group: Group, zone: Zone) => void): () => void
	onTransition(callback: (entity: any, newZone: Zone) => void): () => void
	onPlayerTransition(callback: (player: Player, newZone: Zone) => void): () => void
	onLocalPlayerTransition(callback: (newZone: Zone) => void): () => void
	setEnabled(enabled: boolean): Observer
	setSafety(enabled: boolean): Observer
	setPriority(p: number): Observer
	setUpdateRate(hz: number): Observer
	setPrecision(n: number): Observer
	isEnabled(): boolean
	isPointInside(position: Vector3): boolean
	isSafe(): boolean
	getId(): number
	getPriority(): number
	getUpdateRate(): number
	getPrecision(): number
	getEntitiesInside(): any[]
	getPlayersInside(): Player[]
	getZones(): Zone[]
	getGroups(): Group[]
	getZoneOfEntity(entity: Entity): Zone | undefined
	getZoneOfPlayer(player: Player): Zone | undefined
	getEntitiesInZone(zone: Zone): any[]
	getPlayersInZone(zone: Zone): Player[]
	iterZones(): IterableFunction<Zone>
	iterGroups(): IterableFunction<Group>
	iterEntitiesInside(): IterableFunction<LuaTuple<[Entity, Zone]>>
	iterPlayersInside(): IterableFunction<LuaTuple<[Player, Zone]>>
	iterEntitiesInZone(zone: Zone): IterableFunction<Entity>
	iterPlayersInZone(zone: Zone): IterableFunction<Player>
	onDestroy(callback: () => void): () => void
	destroy(): void
}

export interface GroupConfig {
	entities?: any[]
	autoClean?: boolean
}

export interface Group {
	setAutoClean(enabled: boolean): Group
	add(entity: any): Group
	addBulk(entities: any[]): Group
	remove(entity: any): Group
	removeBulk(entities: any[]): Group
	clear(): Group
	contains(entity: any): boolean
	getId(): number
	getEntities(): any[]
	iterEntities(): IterableFunction<any>
	onDestroy(callback: () => void): () => void
	destroy(): void
}
export interface QuickZone {
	configure(config: { enabled?: boolean; autoSyncRate?: number; frameBudget?: number }): QuickZone
	setEnabled(enabled: boolean): QuickZone
	update(dt: number): QuickZone
	setAutoSyncRate(hz: number): QuickZone
	rebuild(): QuickZone
	setReference(entity: Entity, reference?: any): QuickZone
	setFrameBudget(ms: number): QuickZone
	removeEntity(entity: Entity): QuickZone
	getEntityOfReference(reference: any): Entity | undefined
	getReferenceOfEntity(entity: Entity): any
	getObservers(): Observer[]
	getGroups(): Group[]
	getZones(): Zone[]
	getEntities(): Entity[]
	getZonesAtPoint(position: Vector3): Zone[]
	getZonesOfEntity(entity: Entity): Zone[]
	getGroupsOfEntity(entity: Entity): Group[]
	iterGroups(): IterableFunction<Group>
	iterZones(): IterableFunction<Zone>
	iterEntities(): IterableFunction<Entity>
	iterObservers(): IterableFunction<Observer>
	iterGroupsOfEntity(entity: Entity): IterableFunction<Group>
	iterZonesOfEntity(entity: Entity): IterableFunction<Zone>
	iterZonesAtPoint(point: Vector3): IterableFunction<Zone>
	visualize(enabled: boolean): QuickZone

	Zone: {
		new (config: {
			cframe: CFrame
			size: Vector3
			shape?: ShapeType
			reference?: BasePart | Attachment | Bone
			isDynamic?: boolean
			metadata?: any
			autoSync?: boolean
			observers?: Observer[]
		}): Zone

		fromPart: (part: BasePart, config?: { isDynamic?: boolean; metadata?: any; autoSync?: boolean; observers?: Observer[] }) => Zone
		fromParts: (parts: BasePart[], config?: { isDynamic?: boolean; metadata?: any; autoSync?: boolean; observers?: Observer[] }) => Zones
		fromChildren: (parent: Instance, config?: { isDynamic?: boolean; metadata?: any; autoSync?: boolean; observers?: Observer[] }) => Zones
		fromDescendants: (parent: Instance, config?: { isDynamic?: boolean; metadata?: any; autoSync?: boolean; observers?: Observer[] }) => Zones
		fromTag: (tag: string, config?: { isDynamic?: boolean; metadata?: any; autoSync?: boolean; observers?: Observer[] }) => Zones
	}

	Observer: {
		new (config?: ObserverConfig): Observer
	}

	Group: {
		new (config?: GroupConfig): Group
		fromTag: (tag: string) => Group
		players: () => Group
		localPlayer: () => Group
	}
}

declare const QuickZone: QuickZone
export = QuickZone