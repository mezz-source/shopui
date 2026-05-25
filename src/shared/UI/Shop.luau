local ShopUI = {}
ShopUI.__index = ShopUI

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local Player = Players.LocalPlayer

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GUIs = ReplicatedStorage:WaitForChild("GUIs")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Camera = workspace.CurrentCamera
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RemoteInfo = Remotes:WaitForChild("GetWeaponInfo")
local RemoteInfoAll = Remotes:WaitForChild("GetAllInfoForCategory")

local WeaponPreviews = ReplicatedStorage:WaitForChild("WeaponPreview")

local ShopInfos = ReplicatedStorage.ShopClient.ShopInfos

local Shops = workspace:WaitForChild("Shops")

type Category = "Gun" | "Melee" | "Armor"
type Weight = "Light" | "Moderate" | "Heavy"

type Pill = { Text: string, Color: Color3 }

type FilterInfo = {
	FilterType: string,
	Name: string,
	Order: number,
	Image: string?,
}

type ShopInfo = {
	Name: string,
	Category: Category,
	Filters: { FilterInfo },
}

type ArmorInfo = {
	BulletResistance: number,
	SharpResistance: number,
	BluntResistance: number,
	ArmorType: string,
}

type MeleeInfo = {
	Damage: number,
	SwingDebounce: number,
	DamageType: string,
}

type GunInfo = {
	FireType: "Auto" | "Semi" | "Burst",
	Damage: number,
	Firerate: number,
	Bullets: number,
	BulletSpeed: number,
	Spread: number,
	Range: number,
	ReloadTime: number,
	ZoomFOV: number,
	Recoil: number, -- 10 low, 30 moderate, 50 high
	HeadshotMultiplier: number,
	DamageType: string,
}

type WeaponInfo = {
	Name: string,
	Category: Category,
	Weight: Weight,
	Price: number,
	Level: number,
	Lore: string,
	SpecialText: string,
	GroupUnlocked: boolean,
	Consumable: boolean,
	MaxStack: number?,
	PreviewImage: string,
	ItemInfo: ArmorInfo | MeleeInfo | GunInfo,
	Pills: { Pill },
}

local DAMAGE_TYPE_TO_COLOR = {
	Bullet = Color3.new(0.8, 0.8, 0.8),
	Special = Color3.new(1, 1, 0),
	Sharp = Color3.new(1, 0, 0),
	Blunt = Color3.new(1, 0.4, 0),
}

local SOUND_MAP = {
	Select = { SoundId = "rbxassetid://124033101073224" },
	Hover = { SoundId = "rbxassetid://139295675611093" },
	EndHover = { SoundId = "rbxassetid://139295675611093", PlaybackSpeed = 0.8, Volume = 0.3 },
	Purchase = { SoundId = "rbxassetid://134535509531927" },
	Error = { SoundId = "rbxassetid://8466981206" },
}

local CAMERA_MOUSE_INFLUENCE = 0.24
local CAMERA_LERP_ALPHA = 0.01

local function clamp01(value: number): number
	if value < 0 then
		return 0
	end
	if value > 1 then
		return 1
	end
	return value
end

local function normalized(value: number, minValue: number, maxValue: number): number
	if maxValue <= minValue then
		return 0
	end
	return clamp01((value - minValue) / (maxValue - minValue))
end

local function firerateToShotsPerSecond(firerate: number): number
	if firerate <= 0 then
		return 0
	end

	-- Support common formats:
	-- 1) rounds-per-minute values (usually >= 20)
	-- 2) seconds-per-shot values (usually < 1)
	-- 3) already shots-per-second values (everything else)
	if firerate >= 20 then
		return firerate / 60
	end

	if firerate < 1 then
		return 1 / firerate
	end

	return firerate
end

local function scoreZoomFOV(zoomFOV: number): number
	-- 20-40 is the strong/"decent" range, but sub-20 should still visibly register.
	if zoomFOV <= 20 then
		return normalized(zoomFOV, 0, 20) * 0.45
	end

	if zoomFOV <= 40 then
		return 0.45 + normalized(zoomFOV, 20, 40) * 0.45
	end

	return 0.9 + normalized(zoomFOV, 40, 55) * 0.1
end

local GUN_BASELINES = {
	Auto = {
		damage = { min = 10, max = 42 },
		firerate = { min = 3.5, max = 14 },
		dps = { min = 55, max = 300 },
		recoil = { min = 8, max = 48 },
		clip = { min = 18, max = 60 },
		reload = { min = 1.7, max = 3.8 },
	},
	Semi = {
		damage = { min = 18, max = 75 },
		firerate = { min = 1.6, max = 8 },
		dps = { min = 45, max = 260 },
		recoil = { min = 10, max = 55 },
		clip = { min = 6, max = 26 },
		reload = { min = 1.5, max = 3.4 },
	},
	Burst = {
		damage = { min = 14, max = 52 },
		firerate = { min = 2.4, max = 10.5 },
		dps = { min = 70, max = 320 },
		recoil = { min = 9, max = 52 },
		clip = { min = 12, max = 36 },
		reload = { min = 1.6, max = 3.6 },
	},
}

local function _getShopInfo(shopName: string): ShopInfo
	local info = ShopInfos:FindFirstChild(shopName)
	assert(info, "Missing shop info " .. shopName)
	return require(info)
end

local function _getWeaponInfo(weaponName: string): WeaponInfo?
	return RemoteInfo:InvokeServer(weaponName)
end

local function _getAllWeaponInfosForCategory(category: Category): { WeaponInfo }
	local infos = RemoteInfoAll:InvokeServer({ category = category })
	if not infos then
		warn("No info provided")
	end
	return infos or {}
end

local function _queryAllWeapons(queryTable): { WeaponInfo }
	local infos = RemoteInfoAll:InvokeServer(queryTable)
	if not infos then
		warn("No info provided")
	end
	return infos or {}
end

local function lockCamera()
	Camera.CameraType = Enum.CameraType.Scriptable
end

local function returnCamera()
	Camera.CameraType = Enum.CameraType.Custom
end

local function tweenCameraCFrame(newCFrame: CFrame)
	local tweenInfo = TweenInfo.new(1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	local tween = TweenService:Create(Camera, tweenInfo, { CFrame = newCFrame })
	tween:Play()
end

local function getCurrentMoney()
	local leaderstats = Player:WaitForChild("leaderstats")
	local Money = leaderstats:WaitForChild("Money")
	return Money.Value
end

local function shouldBeLocked(requiredLevel: number, requiredMoney: number): { isUnlocked: boolean, reason: string }
	local leaderstats = Player:WaitForChild("leaderstats")
	local Money = leaderstats:WaitForChild("Money")
	local Level = leaderstats:WaitForChild("Level")

	local Reason = ""
	local Unlocked = true

	if Money.Value < requiredMoney then
		Reason = Reason .. "Money"
		Unlocked = false
	end

	if Level.Value < requiredLevel then
		Reason = Reason .. "Level"
		Unlocked = false
	end

	return { isUnlocked = Unlocked, reason = Reason }
end

function ShopUI.new(shopModelName: string)
	local Shop = Shops:FindFirstChild(shopModelName)
	if not Shop then
		warn(`No shop named {shopModelName} was found, could not create shop`)
		return
	end

	assert(Shop:FindFirstChild("ShopMusic"), "No shop music")
	assert(Shop:FindFirstChild("Shop"), "No shop model")
	assert(Shop:FindFirstChild("CameraPart"), "No camera part")

	local self = setmetatable({}, ShopUI)
	local shopGui = GUIs.Shop:Clone()
	shopGui.Parent = Player.PlayerGui
	self.shopInfo = _getShopInfo(shopModelName)
	self.gui = shopGui
	self.sounds = {}

	self.CameraPart = Shop.CameraPart
	self.ShopMusic = Shop.ShopMusic
	self.ShopMusic.Volume = 0.3

	self.ShopModel = Shop.Shop
	self.ShopName = shopModelName

	local UIFrame = self.gui.Main.UI

	local MenuOptions = UIFrame.MenuOptions.Options

	local WeaponInfo = UIFrame.WeaponInfo :: Frame
	local LoreBox = WeaponInfo.LoreBox :: Frame
	local PurchaseArea = WeaponInfo.PurchaseArea :: Frame
	local PurchaseButton = PurchaseArea.TextButton :: TextButton

	local WeaponPreview = UIFrame.WeaponPreview :: Frame
	local ViewportFrame = WeaponPreview.ViewportFrame :: ViewportFrame

	local WeaponSelection = UIFrame.WeaponSelection :: Frame
	local ScrollingFrame = WeaponSelection.ScrollingFrame :: ScrollingFrame
	local Filters = WeaponSelection.Filters :: Frame

	local WeaponStats = UIFrame.WeaponStats.Stats :: Frame
	local Bars = WeaponStats.Bars :: Frame
	local Pills = WeaponStats.Pills :: Frame
	local ExitButton = UIFrame.Exit :: TextButton
	local _CurrencyOwnedText = UIFrame.CurrencyOwned :: TextLabel

	self.MainFrame = UIFrame
	self.MenuOptions = MenuOptions
	self.WeaponInfo = WeaponInfo
	self.WeaponPreview = WeaponPreview
	self.WeaponSelection = WeaponSelection
	self.WeaponStats = WeaponStats

	self.LoreBox = LoreBox
	self.PurchaseArea = PurchaseArea
	self.PurchaseButton = PurchaseButton

	self.ViewportFrame = ViewportFrame

	self.ScrollingFrame = ScrollingFrame
	self.Filters = Filters

	self.Bars = Bars
	self.Pills = Pills
	self.Exit = ExitButton

	self.alive = false
	self.currentFilter = ""

	local previewCamera = Instance.new("Camera")
	previewCamera.CFrame = CFrame.new(Vector3.zero)
	self.ViewportFrame.CurrentCamera = previewCamera

	self.PreviewCamera = previewCamera
	self.previewConnection = nil
	self.previewModel = nil
	self.previewWorldModel = nil
	self.previewAngle = 0
	self.previewBasePivot = nil

	local colorCorrection = Instance.new("ColorCorrectionEffect", Camera)
	local blurEffect = Instance.new("BlurEffect", Camera)
	blurEffect.Size = 0
	colorCorrection.TintColor = Color3.new(1, 1, 1)

	self.blurEffect = blurEffect
	self.colorCorrection = colorCorrection

	self.MainFrame.Position = UDim2.new(0.5, 0, 2, 0)
	self.baseCameraCFrame = self.CameraPart.CFrame
	self.connection = nil

	self:Init()

	return self
end

function ShopUI:ClearWeaponPreview()
	if self.previewConnection then
		self.previewConnection:Disconnect()
		self.previewConnection = nil
	end

	if self.previewModel then
		self.previewModel:Destroy()
		self.previewModel = nil
	end

	if self.previewWorldModel then
		self.previewWorldModel:Destroy()
		self.previewWorldModel = nil
	end

	self.previewBasePivot = nil
	self.previewAngle = 0
	self.ViewportFrame:ClearAllChildren()
	self.ViewportFrame.CurrentCamera = self.PreviewCamera
end

function ShopUI:SetupWeaponPreview(weaponName: string)
	self:ClearWeaponPreview()

	local model = WeaponPreviews:FindFirstChild(weaponName)
	if not model then
		warn("No preview model", weaponName)
		return
	end
	if not model:IsA("Model") then
		warn("Not a model", weaponName)
		return
	end
	if not model.PrimaryPart then
		warn("No primary part for model", weaponName)
		return
	end

	local previewClone = model:Clone()
	previewClone:PivotTo(CFrame.new())

	local worldModel = Instance.new("WorldModel")
	worldModel.Parent = self.ViewportFrame
	previewClone.Parent = worldModel

	self.previewModel = previewClone
	self.previewWorldModel = worldModel
	self.previewBasePivot = previewClone:GetPivot()

	local _, boundsSize = previewClone:GetBoundingBox()
	local cameraDistance = math.max(boundsSize.X, boundsSize.Y + 0.3, boundsSize.Z) * 1.7 + 1.25
	self.PreviewCamera.CFrame =
		CFrame.new(Vector3.new(0, boundsSize.Y * 0.1, cameraDistance), Vector3.new(0, boundsSize.Y * 0.1, 0))

	self.previewConnection = RunService.RenderStepped:Connect(function(deltaTime)
		if not self.alive or not self.previewModel or not self.previewBasePivot then
			return
		end

		self.previewAngle += deltaTime * 0.6
		self.previewModel:PivotTo(self.previewBasePivot * CFrame.Angles(0, self.previewAngle, 0))
	end)
end

function ShopUI:LoadStats(weaponInfo: WeaponInfo)
	local weaponStats = self.WeaponStats :: Frame
	local Bars = weaponStats.Bars :: Frame
	local Pills = weaponStats.Pills :: Frame
	local BarRef = Bars.BarReference :: Frame
	local PillRef = Pills.PillReference :: Frame

	for _, barFrame in ipairs(Bars:GetChildren()) do
		if barFrame.Name ~= "BarReference" and barFrame:IsA("Frame") then
			barFrame:Destroy()
		end
	end

	for _, pillFrame in ipairs(Pills:GetChildren()) do
		if pillFrame:IsA("Frame") and pillFrame.Name ~= "PillReference" then
			pillFrame:Destroy()
		end
	end

	local function createBar(barLabel: string, fillLevel: number)
		local barFrame = BarRef:Clone() :: Frame
		local bar = barFrame.Bar :: Frame
		local fill = bar.Fill :: Frame
		local label = bar.Label :: TextLabel

		fillLevel = clamp01(fillLevel)
		label.Text = string.upper(barLabel)

		fill.Size = UDim2.new(0, 0, 1, 0)

		if fillLevel < 0.3 then
			fill.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
			label.TextColor3 = Color3.new(1, 0, 0)
		elseif fillLevel == 1 then
			fill.BackgroundColor3 = Color3.fromRGB(255, 255, 0)
			label.TextColor3 = Color3.fromRGB(255, 255, 0)
		end

		barFrame.Name = barLabel
		barFrame.Visible = true
		barFrame.Parent = Bars
		fill:TweenSize(UDim2.new(fillLevel, 0, 1, 0), Enum.EasingDirection.Out, Enum.EasingStyle.Quint, 1, true)
	end

	local function createPill(pillText: string, color: Color3)
		local pill = PillRef:Clone() :: Frame
		local label = pill.Pill :: TextLabel
		label.Text = string.upper(pillText)
		label.BackgroundColor3 = color
		pill.BackgroundColor3 = Color3.new(color.R * 0.8, color.G * 0.8, color.B * 0.8)
		pill.Visible = true
		pill.Name = pillText
		pill.Parent = Pills
	end

	if weaponInfo.Category == "Gun" then
		local gunInfo = weaponInfo.ItemInfo :: GunInfo
		local baseline = GUN_BASELINES[gunInfo.FireType] or GUN_BASELINES.Auto
		local shotsPerSecond = firerateToShotsPerSecond(gunInfo.Firerate)
		local estimatedDPS = gunInfo.Damage * shotsPerSecond

		local rawDamageScore = normalized(gunInfo.Damage, baseline.damage.min, baseline.damage.max)
		local dpsDamageScore = normalized(estimatedDPS, baseline.dps.min, baseline.dps.max)
		local damageScore = clamp01(rawDamageScore * 0.4 + dpsDamageScore * 0.6)
		local rateScore = normalized(shotsPerSecond, baseline.firerate.min, baseline.firerate.max)

		-- Lower recoil handles better, so invert the normalized score.
		local handleScore = 1 - normalized(gunInfo.Recoil, baseline.recoil.min, baseline.recoil.max)

		-- Reward bigger clips and fast reloads, but punish the combo of tiny clip + slow reload.
		local clipScore = normalized(gunInfo.Bullets, baseline.clip.min, baseline.clip.max) * 0.55
			+ (1 - normalized(gunInfo.ReloadTime, baseline.reload.min, baseline.reload.max)) * 0.45

		if gunInfo.Bullets <= baseline.clip.min + 2 and gunInfo.ReloadTime >= baseline.reload.max - 0.2 then
			clipScore *= 0.75
		end

		local zoomScore = scoreZoomFOV(gunInfo.ZoomFOV)

		createBar("DMG", damageScore)
		createBar("RATE", rateScore)
		createBar("HANDLE", handleScore)
		createBar("CLIP", clipScore)
		createBar("ZOOM", zoomScore)

		local damageColor = DAMAGE_TYPE_TO_COLOR[gunInfo.DamageType] or Color3.new(1, 1, 0)
		createPill(gunInfo.DamageType, damageColor)
	else
		createBar("DMG", 0)
		createBar("RATE", 0)
		createBar("HANDLE", 0)
		createBar("CLIP", 0)
		createBar("ZOOM", 0)
	end

	for _, pill: Pill in ipairs(weaponInfo.Pills) do
		createPill(pill.Text, pill.Color)
	end
end

function ShopUI:SelectWeapon(weaponName: string)
	local weaponInfo = _getWeaponInfo(weaponName) :: WeaponInfo
	if not weaponInfo then
		warn("No weapon info", weaponName)
		return
	end

	self.LoreBox.TextLabel.Text = weaponInfo.Lore
	self.WeaponInfo.WeaponTitle.Text = weaponInfo.Name
	self.WeaponStats.SpecialText.Text = weaponInfo.SpecialText
	self.PurchaseArea.Visible = true
	self.PurchaseButton.Text = "※ " .. weaponInfo.Price

	local result = shouldBeLocked(weaponInfo.Level, weaponInfo.Price)
	if result["isUnlocked"] then
		self.PurchaseButton.BackgroundColor3 = Color3.new(1, 1, 1)
	else
		self.PurchaseButton.BackgroundColor3 = Color3.new(1, 0, 0)
	end

	self:SetupWeaponPreview(weaponName)
	self:LoadStats(weaponInfo)
end

function ShopUI:SelectFilter(filterType: "Weight", filter)
	if self.currentFiler == filter then
		return
	end

	self.currentFiler = filter

	if filterType == "Weight" then
		local info = _queryAllWeapons({
			category = self.shopInfo.Category,
			weights = filter,
		})
		self:LoadWeaponInfos(info)
	else
		warn("unimplemented", filterType)
	end
end

function ShopUI:LoadWeaponInfos(info: { WeaponInfo })
	local selectionReference = self.ScrollingFrame.Reference

	-- remove existing frames
	for _, child in ipairs(self.ScrollingFrame:GetChildren()) do
		if child:IsA("TextButton") and child.Name ~= "Reference" then
			child:Destroy()
		end
	end

	for name, info: WeaponInfo in pairs(info) do
		local weaponTextButton = selectionReference:Clone() :: TextButton
		weaponTextButton.Visible = true

		local DisplayImage = weaponTextButton.ImageLabel :: ImageLabel
		local Cost = weaponTextButton.Cost :: TextLabel
		local Level = weaponTextButton.Level :: TextLabel
		local Title = weaponTextButton.Title :: TextLabel
		weaponTextButton.Name = Title.Text

		DisplayImage.Image = info.PreviewImage
		Title.Text = info.Name
		Level.Text = "LVL " .. info.Level
		Cost.Text = "※ " .. info.Price
		weaponTextButton.Parent = self.ScrollingFrame

		-- TODO: why are we using strings for this
		local result = shouldBeLocked(info.Level, info.Price)
		local isUnlocked, reason = result["isUnlocked"], result["reason"]

		if not isUnlocked then
			if reason == "MoneyLevel" then
				Level.TextColor3 = Color3.new(1, 0, 0)
				Cost.TextColor3 = Color3.new(1, 0, 0)
			elseif reason == "Money" then
				Cost.TextColor3 = Color3.new(1, 0, 0)
			elseif reason == "Level" then
				Level.TextColor3 = Color3.new(1, 0, 0)
			end

			weaponTextButton.ImageLabel.ImageTransparency = 0.5
			weaponTextButton.Title.BackgroundColor3 = Color3.new(1, 0, 0)
		end

		weaponTextButton.MouseButton1Down:Connect(function()
			self:SelectWeapon(info.Name)
		end)

		self:HookBaseButtonSounds(weaponTextButton, 0.04)
	end
end

function ShopUI:LoadFilters()
	local filterReference = self.Filters.FilterReference
	warn("Filter info:", self.shopInfo.Filters)
	for _, filter: FilterInfo in ipairs(self.shopInfo.Filters) do
		local filterFrame = filterReference:Clone()
		local imageButton = filterFrame:WaitForChild("ImageButton") :: ImageButton
		imageButton.Image = filter.Image

		filterFrame.Name = filter.Name
		filterFrame.LayoutOrder = filter.Order
		filterFrame.Visible = true
		filterFrame.Parent = self.Filters

		imageButton.MouseButton1Down:Connect(function()
			for _, button in ipairs(filterFrame.Parent:GetChildren()) do
				if button:IsA("Frame") then
					local imageButton = button:FindFirstChild("ImageButton")
					if imageButton then
						imageButton.ImageColor3 = Color3.new(1, 1, 1)
					end
				end
			end

			self:SelectFilter(filter.FilterType, filter.Name)
			imageButton.ImageColor3 = Color3.new(0.533333, 0.533333, 0.533333)
		end)
	end
end

function ShopUI:HookBaseButtonSounds(button: TextButton | ImageButton, scaleModifierAmount: number?)
	local scaleModifier = Instance.new("UIScale", button)

	button.MouseEnter:Connect(function()
		if not self.alive then
			return
		end
		TweenService:Create(
			scaleModifier,
			TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
			{ Scale = 1 + (scaleModifierAmount or 0.07) }
		):Play()

		self:PlaySound("Hover")
	end)

	button.MouseLeave:Connect(function()
		if not self.alive then
			return
		end
		TweenService
			:Create(scaleModifier, TweenInfo.new(0.4, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { Scale = 1 })
			:Play()

		self:PlaySound("EndHover")
	end)

	button.MouseButton1Down:Connect(function()
		if not self.alive then
			return
		end
		self:PlaySound("Select")
	end)
end

function ShopUI:PlaySound(soundName: string)
	local sound = self.sounds[soundName]
	if not sound then
		warn(`No sound named {soundName} was found`)
		return
	end

	sound:Play()
end

function ShopUI:LoadSounds()
	for soundName, propertyList in pairs(SOUND_MAP) do
		local newSound = Instance.new("Sound", workspace)
		newSound.Name = soundName .. "UI"

		for propertName, _ in pairs(propertyList) do
			newSound[propertName] = propertyList[propertName]
		end

		self.sounds[soundName] = newSound
	end
end

function ShopUI:InitButtons()
	self.Exit.MouseButton1Down:Connect(function()
		self:Hide(true)
	end)

	for _, desc in ipairs(self.MainFrame:GetDescendants()) do
		if desc:IsA("TextButton") or desc:IsA("ImageButton") then
			self:HookBaseButtonSounds(desc)
		end
	end
end

function ShopUI:Init()
	self.MainFrame.CurrencyOwned.Text = "※ " .. tostring(getCurrentMoney())
	self:LoadFilters()
	self:LoadSounds()
	self:InitButtons()
	self:SetupRenderConnect()
	self:Show(true)

	_getAllWeaponInfosForCategory(self.shopInfo.Category)
	self:SelectFilter(self.shopInfo.Filters[1].FilterType, self.shopInfo.Filters[1].Name)
end

function ShopUI:SetupRenderConnect()
	if self.connection then
		self.connection:Disconnect()
	end

	self.connection = RunService.RenderStepped:Connect(function()
		if not self.alive or Camera.CameraType ~= Enum.CameraType.Scriptable then
			return
		end

		local viewportSize = Camera.ViewportSize
		if viewportSize.X <= 0 or viewportSize.Y <= 0 then
			return
		end

		local mouse = UserInputService:GetMouseLocation()
		local normalizedX = ((mouse.X / viewportSize.X) - 0.5) * 2
		local normalizedY = ((mouse.Y / viewportSize.Y) - 0.5) * 2

		local rightOffset = normalizedX * CAMERA_MOUSE_INFLUENCE
		local upOffset = -normalizedY * CAMERA_MOUSE_INFLUENCE

		local targetCFrame = self.baseCameraCFrame * CFrame.new(rightOffset, upOffset, 0)
		Camera.CFrame = Camera.CFrame:Lerp(targetCFrame, CAMERA_LERP_ALPHA)
	end)
end

function ShopUI:Show(entering: boolean)
	self.alive = true

	if entering then
		lockCamera()
		self.baseCameraCFrame = self.CameraPart.CFrame
		tweenCameraCFrame(self.CameraPart.CFrame)
		self.ShopMusic:Play()
		Player:SetAttribute("InShop", true)
	end

	self:TweenBlur(24)
	self:TweenTintColor(Color3.new(0.647059, 0.647059, 0.647059))

	local main = self.MainFrame :: Frame
	main:TweenPosition(UDim2.new(0.5, 0, 0.5, 0), Enum.EasingDirection.Out, Enum.EasingStyle.Quint, 1.5, true)
end

function ShopUI:Hide(exitting: boolean)
	self.alive = false
	local main = self.MainFrame :: Frame

	if exitting then
		returnCamera()
		TweenService
			:Create(self.ShopMusic, TweenInfo.new(1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { Volume = 0 })
			:Play()
		Player:SetAttribute("InShop", false)
	end

	self:TweenBlur(0)
	self:TweenTintColor(Color3.new(1, 1, 1))

	main:TweenPosition(UDim2.new(0.5, 0, 2, 0), Enum.EasingDirection.Out, Enum.EasingStyle.Quint, 1, true, function()
		if exitting then
			task.delay(3, function()
				self:Destroy()
			end)
		end
	end)
end

function ShopUI:TweenBlur(newSize)
	if not self.blurEffect then
		return
	end
	TweenService
		:Create(
			self.blurEffect,
			TweenInfo.new(2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
			{ Size = newSize }
		)
		:Play()
end

function ShopUI:TweenTintColor(newColor: Color3)
	if not self.colorCorrection then
		return
	end
	TweenService:Create(
		self.colorCorrection,
		TweenInfo.new(2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
		{ TintColor = newColor }
	):Play()
end

function ShopUI:Destroy()
	self:ClearWeaponPreview()

	if self.connection then
		self.connection:Disconnect()
		self.connection = nil
	end

	self.blurEffect:Destroy()
	self.colorCorrection:Destroy()
	self.gui:Destroy()

	for _, sound in pairs(self.sounds) do
		sound:Destroy()
	end
end

return ShopUI
