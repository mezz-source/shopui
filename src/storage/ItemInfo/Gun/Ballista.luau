return {
	Name = "Ballista",
	Category = "Gun",
	Weight = "Heavy",
	Price = 250000,
	Level = 50,
	Lore = "An explosive weapon that has at least 400 DOOMS inside of it",
	SpecialText = "Fires an explosive projectile. Self knockback is high.",
	GroupUnlocked = true,
	Consumable = false,
	IsTorsoDominant = true,
	PreviewImage = "rbxassetid://126642939804663",

	ItemInfo = {
		DamageType = "Special",
	},

	PreviewModelOrientationOffset = Vector3.new(0, 0, 1),
	PreviewCameraOffset = Vector3.new(0, 0, -6),

	Pills = {
		{ Text = "EXPLOSIVE", Color = Color3.new(1, 0, 0) },
		{ Text = "KNOCKBACK", Color = Color3.new(1, 0.6, 0) },
	},
}
