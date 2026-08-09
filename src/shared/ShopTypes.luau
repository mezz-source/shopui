local ShopTypes = {}

export type Category = "Gun" | "Melee" | "Armor"
export type Weight = "Light" | "Moderate" | "Heavy"

export type Pill = {
	Text: string,
	Color: Color3,
}

export type FilterInfo = {
	FilterType: string,
	Name: string,
	Order: number,
	Image: string?,
}

export type ShopInfo = {
	ShopName: string,
	Category: Category,
	Filters: { FilterInfo },
}

export type ArmorInfo = {
	BulletResistance: number,
	SharpResistance: number,
	BluntResistance: number,
	ArmorType: string,
}

export type MeleeInfo = {
	DamageAmount: number,
	DamageDeviation: number,
	DamageType: string,
	Debounce: number,
	KnockbackPower: number,
	SignalessEndTime: number,
	SignalessSwingTime: number,
}

export type Loadout = {
	[number]: string,
}

export type LoadoutConfig = {
	maxSlots: number,
	maxWeight: number,
	lightWeaponWeight: number,
	mediumWeaponWeight: number,
	heavyWeaponWeight: number,
}

export type WeaponSlot = {
	CurrentItem: string | "None",
	Weight: "Light" | "Moderate" | "Heavy" | nil,
	SlotIndex: number,
	Button: TextButton,
}

export type WeaponChoice = {
	Name: string,
	Weight: string,
	PreviewImage: string,
	IsTorsoDominant: boolean,
	Button: TextButton,
}

export type GunInfo = {
	FireType: "Auto" | "Semi" | "Burst",
	Damage: number,
	Firerate: number,
	Bullets: number,
	ZoomFOV: number,
	BulletSpeed: number,
	Spread: number,
	Range: number,
	ReloadTime: number,
	Recoil: number,
	HeadshotMultiplier: number,
	DamageType: string,
}

export type ItemInfo = ArmorInfo | MeleeInfo | GunInfo

export type WeaponInfo = {
	Name: string,
	Category: Category,
	Weight: Weight,
	Price: number,
	Level: number,
	Lore: string,
	SpecialText: string,
	BadgeTag: string?,
	GroupId: number?,
	GroupUnlocked: boolean,
	Consumable: boolean,
	MaxStack: number?,
	PreviewImage: string,
	PreviewCameraOffset: Vector3?,
	PreviewModelOrientationOffset: Vector3?,
	ItemInfo: ItemInfo,
	Pills: { Pill },
}

export type GunSettings = {
	BaseDamage: number,
	Auto: boolean,
	BurstFireEnabled: boolean,
	BulletPerBurst: number,
	FireRate: number,
	ReloadTime: number,
	AmmoPerMag: number,
	Spread: number,
	IdleAnimationID: number,
	EquippedAnimationID: number,
	ShotgunEnabled: boolean,
	BulletPerShot: number,
	Recoil: number,
	Range: number,
	ExplosiveEnabled: boolean,
	ExplosionRadius: number,
	FieldOfViewIS: number,
}

export type InfoLibrary = {
	getWeaponInfo: (name: string) -> WeaponInfo?,
	getAllForCategory: (category: Category) -> { WeaponInfo },
	queryWeapons: (category: Category, weights: { Weight }?) -> { WeaponInfo },
	getGunSettings: (name: string) -> GunSettings?,
	getMeleeSettings: (name: string) -> MeleeInfo?,
	getOwnedItems: () -> { string },
	isOwned: (name: string) -> boolean,
	refreshOwnedItems: () -> { string },
	registerOwnedItem: (name: string) -> (),
}

export type ShopQuery = {
	category: Category?,
	weights: Weight | { Weight }?,
	nameContains: string?,
	search: string?,
	priceMin: number?,
	priceMax: number?,
	levelMin: number?,
	levelMax: number?,
	consumable: boolean?,
	groupUnlocked: boolean?,
	customFilters: { [string]: any }?,
	sortBy: string?,
	sortDir: "asc" | "desc"?,
	offset: number?,
	limit: number?,
	fields: { string }?,
	returnType: "map" | "array"?,
	name: string?,
}

return ShopTypes
