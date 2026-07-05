return {
	Name = "Blunderbuss",
	Category = "Gun",
	Weight = "Moderate",
	Price = 500000,
	Level = 60,
	Lore = "A gunpowder weapon that shoots a large amount of pellets. It is very effective at close range. And murder.",
	SpecialText = "Orbital tier knockback for borderline goofy damage",
	GroupUnlocked = true,
	Consumable = false,
	IsTorsoDominant = true,
	PreviewImage = "rbxassetid://81560652783119",

	ItemInfo = {
		DamageType = "Bullet",
	},

	PreviewModelOrientationOffset = Vector3.new(0, 0, 1),
	PreviewCameraOffset = Vector3.new(0, 0, -4),

	Pills = {
		{ Text = "KNOCKBACK", Color = Color3.new(1, 0.6, 0) },
	},
}
