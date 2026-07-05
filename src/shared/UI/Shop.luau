local ShopUI = {}
ShopUI.__index = ShopUI

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local Player = Players.LocalPlayer

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local GUIs = ReplicatedStorage:WaitForChild("GUIs")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Camera = workspace.CurrentCamera
local Remotes = ReplicatedStorage:WaitForChild("ShopRemotes")
local RemoteInfo = Remotes:WaitForChild("GetWeaponInfo")
local RemoteInfoAll = Remotes:WaitForChild("GetAllInfoForCategory")
local GetGunSettings = Remotes:WaitForChild("GetGunSettings")
local GetMeleeSettings = Remotes:WaitForChild("GetMeleeSettings")

local WeaponPreviews = ReplicatedStorage:WaitForChild("WeaponPreview")

local ShopInfos = ReplicatedStorage.ShopClient.ShopInfos
local ShopTypes = require(ReplicatedStorage.ShopClient.ShopTypes)
local GunScoring = require(script.Parent.Parent.GunScoring)
local MeleeScoring = require(script.Parent.Parent.MeleeScoring)
local InvokeLogger = require(script.Parent.Parent.InvokeLogger)

local Shops = workspace:WaitForChild("Shops")

type Category = ShopTypes.Category
type Weight = ShopTypes.Weight
type Pill = ShopTypes.Pill
type FilterInfo = ShopTypes.FilterInfo
type ShopInfo = ShopTypes.ShopInfo
type ArmorInfo = ShopTypes.ArmorInfo
type MeleeInfo = ShopTypes.MeleeInfo
type GunInfo = ShopTypes.GunInfo
type WeaponInfo = ShopTypes.WeaponInfo

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
local PURCHASE_LOADING_DELAY = 0.1
local CURRENCY_ANIMATION_DURATION = 0.8

local function clamp01(value: number): number
	if value < 0 then
		return 0
	end
	if value > 1 then
		return 1
	end
	return value
end

local function getPreviewCameraOffset(weaponInfo: WeaponInfo?): Vector3
	if weaponInfo and weaponInfo.PreviewCameraOffset then
		return weaponInfo.PreviewCameraOffset
	end

	return Vector3.zero
end

local function getPreviewModelSpinAxis(weaponInfo: WeaponInfo?): Vector3
	local orientationOffset = if weaponInfo then weaponInfo.PreviewModelOrientationOffset else nil
	if orientationOffset and orientationOffset.Magnitude > 0 then
		return orientationOffset.Unit
	end

	return Vector3.yAxis
end

---------

local function formatNumber(num: number): string
	local formatted = tostring(math.floor(num))
	local count
	while true do
		formatted, count = formatted:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
		if count == 0 then
			break
		end
	end

	return formatted
end

local function _getShopInfo(shopName: string): ShopInfo
	local info = ShopInfos:FindFirstChild(shopName)
	assert(info, "Missing shop info " .. shopName)
	return require(info)
end

local function _getWeaponInfo(weaponName: string): WeaponInfo?
	return InvokeLogger.invokeServer(RemoteInfo, weaponName)
end

local function _getAllWeaponInfosForCategory(category: Category): { WeaponInfo }
	local infos = InvokeLogger.invokeServer(RemoteInfoAll, { category = category })
	if not infos then
		warn("No info provided")
	end
	return infos or {}
end

local function _queryAllWeapons(queryTable): { WeaponInfo }
	local infos = InvokeLogger.invokeServer(RemoteInfoAll, queryTable)
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

local function getEnabledCoreGuis(): { Enum.CoreGuiType }
	local enabledCoreGuis = {}

	for _, coreGuiType in ipairs(Enum.CoreGuiType:GetEnumItems()) do
		if coreGuiType ~= Enum.CoreGuiType.All and coreGuiType ~= Enum.CoreGuiType.ExperienceShop then
			local success, enabled = pcall(function()
				return StarterGui:GetCoreGuiEnabled(coreGuiType)
			end)

			if success and enabled then
				table.insert(enabledCoreGuis, coreGuiType)
			end
		end
	end

	return enabledCoreGuis
end

local function tweenCameraCFrame(newCFrame: CFrame)
	local tweenInfo = TweenInfo.new(1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	local tween = TweenService:Create(Camera, tweenInfo, { CFrame = newCFrame })
	tween:Play()
end

local function getCurrentMoney()
	local leaderstats = Player:WaitForChild("leaderstats")
	local Money = leaderstats:WaitForChild("Credits")
	return Money.Value
end

local function getCurrentLevel()
	local leaderstats = Player:WaitForChild("leaderstats")
	local Level = leaderstats:WaitForChild("Level")
	return Level.Value
end

local function shouldBeLocked(requiredLevel: number, requiredMoney: number): { isUnlocked: boolean, reason: string }
	local leaderstats = Player:WaitForChild("leaderstats")
	local Money = leaderstats:WaitForChild("Credits")
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

local function hasBadgeUnlocked(_badgeTag: string): boolean
	-- Stubbed for now; replace with your badge ownership logic.
	return true
end

local function isInRequiredGroup(groupId: number): boolean
	local success, isInGroup = pcall(function()
		return Player:IsInGroup(groupId)
	end)

	if not success then
		warn("Failed to check group requirement for group ID", groupId)
		return false
	end

	return isInGroup
end

local function getRequirementLockState(weaponInfo: WeaponInfo): { isUnlocked: boolean, lockText: string }
	local badgeTag = weaponInfo.BadgeTag
	local groupId = weaponInfo.GroupId

	if badgeTag == nil and groupId == nil then
		return { isUnlocked = true, lockText = "" }
	end

	local badgeUnlocked = false
	if badgeTag ~= nil and badgeTag ~= "" then
		badgeUnlocked = hasBadgeUnlocked(badgeTag)
	end

	local groupUnlocked = false
	if groupId ~= nil and groupId > 0 then
		groupUnlocked = isInRequiredGroup(groupId)
	end

	if badgeUnlocked or groupUnlocked then
		return { isUnlocked = true, lockText = "" }
	end

	if badgeTag ~= nil and badgeTag ~= "" and groupId ~= nil and groupId > 0 then
		return { isUnlocked = false, lockText = "REQUIRES BADGE " .. badgeTag:upper() .. " OR GROUP ONLY" }
	end

	if badgeTag ~= nil and badgeTag ~= "" then
		return { isUnlocked = false, lockText = "REQUIRES BADGE " .. badgeTag:upper() }
	end

	return { isUnlocked = false, lockText = "GROUP ONLY" }
end

function ShopUI.new(
	shopModelName: string?,
	options: { gui: Instance?, autoStart: boolean?, onExitRequested: (() -> ())? }?
)
	local shopOptions = options :: { gui: Instance?, autoStart: boolean?, onExitRequested: (() -> ())? }?
	local self = setmetatable({}, ShopUI)
	local shopGui = if shopOptions and shopOptions.gui then shopOptions.gui else GUIs.Shop:Clone()
	local autoStart = if shopOptions == nil or shopOptions.autoStart == nil then true else shopOptions.autoStart

	if shopGui.Parent == nil then
		shopGui.Parent = Player.PlayerGui
	end

	self.gui = shopGui
	self.sounds = {}
	self.started = false
	self.onExitRequested = if shopOptions then shopOptions.onExitRequested else nil
	self.shopInfo = nil

	self.CameraPart = nil
	self.ShopModel = nil
	self.ShopName = shopModelName

	if shopModelName then
		local Shop = Shops:FindFirstChild(shopModelName)
		if not Shop then
			warn(`No shop named {shopModelName} was found, could not create shop`)
			return self
		end

		assert(Shop:FindFirstChild("Shop"), "No shop model")
		assert(Shop:FindFirstChild("CameraPart"), "No camera part")

		self.shopInfo = _getShopInfo(shopModelName)
		self.CameraPart = Shop.CameraPart

		self.ShopModel = Shop.Shop
	end

	local UIFrame = self.gui.UI
	local LoadingFrame = self.gui.Loading
	local LoadingIcon = LoadingFrame.LoadingIcon

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
	local _Level = UIFrame.Level :: TextLabel

	local LeftFilter = Filters.LeftFrame.Left :: ImageButton
	local RightFilter = Filters.RightFrame.Right :: ImageButton

	self.LoadingFrame = LoadingFrame
	self.LoadingIcon = LoadingIcon

	self.MainFrame = UIFrame
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
	self.LeftFilter = LeftFilter
	self.RightFilter = RightFilter

	self.Bars = Bars
	self.Pills = Pills
	self.Exit = ExitButton
	self.Exit.MouseButton1Down:Connect(function()
		if self.purchaseInProgress then
			warn("Can't exit while purchase is in progress")
			self:PlaySound("Error")
			return
		end

		if self.onExitRequested then
			self.onExitRequested()
		else
			self:Hide(true)
		end
	end)

	self.alive = false
	self.currentFilter = ""
	self.currentFilterIndex = 0
	self.currentFilterName = nil
	self.filterFrames = {}
	self.filterInfos = {}
	self.enabledCoreGuis = nil
	self.characterAddedConnection = nil
	self.characterDiedConnection = nil
	self.lockedCharacter = nil
	self.lockedHumanoid = nil
	self.lockedRootPart = nil
	self.originalWalkSpeed = nil
	self.originalJumpPower = nil
	self.originalJumpHeight = nil
	self.originalAutoRotate = nil
	self.originalRootAnchored = nil

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
	self.purchaseConnection = nil
	self.currencyConnection = nil
	self.purchaseInProgress = false
	self.purchaseLoadingToken = 0
	self.currencyAnimationToken = 0
	self.currentCurrencyAmount = nil
	self.ownedItems = {}
	self.pendingPurchaseRefreshWeaponName = nil
	self.lastPurchaseRefreshWeaponName = nil
	self.currentWeaponInfoButtons = {}
	self.currentWeaponName = nil

	if autoStart and self.shopInfo then
		self:Start()
	end

	return self
end

function ShopUI:Start()
	if self.started then
		return
	end

	if not self.shopInfo or not self.CameraPart or not self.ShopModel then
		warn("ShopUI cannot start without a valid shop model")
		return
	end

	self.started = true
	self:Init()
end

function ShopUI:UpdateOwnedWeapons()
	local ownedItems = InvokeLogger.invokeServer(Remotes.GetOwnedItems) :: { string }
	if not ownedItems then
		warn("No owned items provided")
		return
	end

	self.ownedItems = ownedItems
end

function ShopUI:RegisterOwnedItem(weaponName: string)
	if table.find(self.ownedItems, weaponName) ~= nil then
		return
	end

	table.insert(self.ownedItems, weaponName)
end

function ShopUI:RefreshPurchasedWeaponState(weaponName: string)
	if self.purchaseInProgress then
		self.pendingPurchaseRefreshWeaponName = weaponName
		return
	end

	if self.lastPurchaseRefreshWeaponName == weaponName then
		return
	end

	self.lastPurchaseRefreshWeaponName = weaponName
	self.pendingPurchaseRefreshWeaponName = nil
	self:RegisterOwnedItem(weaponName)
	self:UpdateWeaponInfos()

	if self.currentWeaponName == weaponName then
		self:SelectWeapon(weaponName)
	end
end

function ShopUI:UpdateCurrencyDisplay(targetAmount: number)
	local currencyText = self.MainFrame.CurrencyOwned :: TextLabel
	local currentAmount = self.currentCurrencyAmount

	if currentAmount == nil then
		self.currentCurrencyAmount = targetAmount
		currencyText.Text = "※ " .. tostring(targetAmount)
		return
	end

	self.currencyAnimationToken += 1
	local currencyAnimationToken = self.currencyAnimationToken
	local startAmount = currentAmount

	if targetAmount >= startAmount then
		self.currentCurrencyAmount = targetAmount
		currencyText.Text = "※ " .. tostring(targetAmount)
		return
	end

	task.spawn(function()
		local startTime = os.clock()
		local duration = CURRENCY_ANIMATION_DURATION

		while self.alive and self.currencyAnimationToken == currencyAnimationToken do
			local progress = math.clamp((os.clock() - startTime) / duration, 0, 1)
			local easedProgress = 1 - (1 - progress) ^ 3
			local displayedAmount = math.floor(startAmount + (targetAmount - startAmount) * easedProgress + 0.5)

			self.currentCurrencyAmount = displayedAmount
			currencyText.Text = "※ " .. tostring(displayedAmount)

			if progress >= 1 then
				break
			end

			task.wait()
		end

		if self.currencyAnimationToken == currencyAnimationToken then
			self.currentCurrencyAmount = targetAmount
			currencyText.Text = "※ " .. tostring(targetAmount)
		end
	end)
end

function ShopUI:OwnsWeapon(weaponName: string): boolean
	return table.find(self.ownedItems, weaponName) ~= nil
end

function ShopUI:ResetWeaponFrameState(weaponFrame)
	local title = weaponFrame.Title :: TextLabel
	local cost = weaponFrame.Cost :: TextLabel
	local level = weaponFrame.Level :: TextLabel
	local image = weaponFrame.ImageLabel :: ImageLabel

	title.BackgroundColor3 = Color3.new(1, 1, 1)
	title.TextColor3 = Color3.new(1, 1, 1)
	cost.TextColor3 = Color3.new(1, 1, 1)
	level.TextColor3 = Color3.new(1, 1, 1)
	image.ImageColor3 = Color3.new(1, 1, 1)
	image.ImageTransparency = 0
end

function ShopUI:ApplyWeaponFrameState(weaponFrame, weaponInfo: WeaponInfo)
	self:ResetWeaponFrameState(weaponFrame)

	local title = weaponFrame.Title :: TextLabel
	local cost = weaponFrame.Cost :: TextLabel
	local level = weaponFrame.Level :: TextLabel
	local image = weaponFrame.ImageLabel :: ImageLabel
	cost.Text = "※ " .. formatNumber(weaponInfo.Price)

	if weaponInfo.Price == 0 then
		cost.Text = ""
	end

	if weaponInfo.Level == 0 then
		level.Text = ""
	end

	if self:OwnsWeapon(weaponInfo.Name) then
		title.BackgroundColor3 = Color3.new(0.062745, 0.2, 0.062745)
		title.TextColor3 = Color3.new(0, 1, 0)
		cost.TextColor3 = Color3.new(0, 1, 0)
		level.TextColor3 = Color3.new(0, 1, 0)
		image.ImageColor3 = Color3.new(0, 1, 0)
		image.ImageTransparency = 0.5
		return
	else
		title.TextColor3 = Color3.new(0, 0, 0)
	end

	local requirementLockState = getRequirementLockState(weaponInfo)
	if not requirementLockState.isUnlocked then
		cost.Text = requirementLockState.lockText
		cost.TextColor3 = Color3.new(1, 0, 0)
		image.ImageTransparency = 0.5
		title.BackgroundColor3 = Color3.new(1, 0, 0)
		return
	end

	local result = shouldBeLocked(weaponInfo.Level, weaponInfo.Price)
	if result.isUnlocked then
		return
	end

	local reason = result.reason
	if reason == "MoneyLevel" then
		level.TextColor3 = Color3.new(1, 0, 0)
		cost.TextColor3 = Color3.new(1, 0, 0)
	elseif reason == "Money" then
		cost.TextColor3 = Color3.new(1, 0, 0)
	elseif reason == "Level" then
		level.TextColor3 = Color3.new(1, 0, 0)
	end

	image.ImageTransparency = 0.5
	title.BackgroundColor3 = Color3.new(1, 0, 0)
end

function ShopUI:ApplySelectedWeaponState(weaponInfo: WeaponInfo)
	self.PurchaseArea.Visible = true
	self.PurchaseButton.BackgroundColor3 = Color3.new(1, 1, 1)
	self.PurchaseButton.Text = "※ " .. formatNumber(weaponInfo.Price)

	if weaponInfo.Price == 0 then
		self.PurchaseButton.Text = "FREE"
	end

	if self:OwnsWeapon(weaponInfo.Name) then
		self.PurchaseButton.Text = "OWNED"
		self.PurchaseButton.BackgroundColor3 = Color3.new(0.4, 0.4, 0.4)
		return
	end

	local requirementLockState = getRequirementLockState(weaponInfo)
	if not requirementLockState.isUnlocked then
		self.PurchaseButton.BackgroundColor3 = Color3.new(1, 0, 0)
		self.PurchaseButton.Text = requirementLockState.lockText
		return
	end

	local result = shouldBeLocked(weaponInfo.Level, weaponInfo.Price)
	if result.isUnlocked then
		return
	end

	self.PurchaseButton.BackgroundColor3 = Color3.new(1, 0, 0)
	if result.reason == "MoneyLevel" then
		self.PurchaseButton.Text = "※ "
			.. formatNumber(weaponInfo.Price)
			.. " | LVL "
			.. formatNumber(weaponInfo.Level)
	elseif result.reason == "Money" then
		self.PurchaseButton.Text = "※ " .. formatNumber(weaponInfo.Price)
	elseif result.reason == "Level" then
		self.PurchaseButton.Text = "LVL " .. formatNumber(weaponInfo.Level)
	end
end

function ShopUI:ExitLoadingState()
	local backgroundTween = TweenService:Create(
		self.LoadingFrame,
		TweenInfo.new(0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		{ BackgroundTransparency = 1 }
	)

	local iconTween = TweenService:Create(
		self.LoadingIcon,
		TweenInfo.new(0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		{ ImageTransparency = 1 }
	)

	iconTween:Play()
	backgroundTween:Play()
end

function ShopUI:StartLoadingState()
	self.LoadingIcon.Position = UDim2.new(0.5, 0, 0.6, 0)
	self.LoadingIcon:TweenPosition(
		UDim2.new(0.5, 0, 0.5, 0),
		Enum.EasingDirection.Out,
		Enum.EasingStyle.Quint,
		0.4,
		true
	)

	local backgroundTween = TweenService:Create(
		self.LoadingFrame,
		TweenInfo.new(0.6, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		{ BackgroundTransparency = 0.5 }
	)

	local iconTween = TweenService:Create(
		self.LoadingIcon,
		TweenInfo.new(0.6, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		{ ImageTransparency = 0 }
	)

	iconTween:Play()
	backgroundTween:Play()
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

	local weaponInfo = _getWeaponInfo(weaponName)

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

	if self.previewConnection then
		--- removes the EPIC SPINNING bug that would happen
		--- if you spam selected
		--- at least in theory....
		self.previewConnection:Disconnect()
	end

	local previewClone = model:Clone()
	local previewClonePivot = previewClone:GetPivot()
	previewClone:PivotTo(CFrame.new() * previewClonePivot.Rotation)

	local worldModel = Instance.new("WorldModel")
	worldModel.Parent = self.ViewportFrame
	previewClone.Parent = worldModel

	self.previewModel = previewClone
	self.previewWorldModel = worldModel
	self.previewBasePivot = previewClone:GetPivot()

	local previewCameraOffset = getPreviewCameraOffset(weaponInfo)
	local previewModelSpinAxis = getPreviewModelSpinAxis(weaponInfo)

	local _, boundsSize = previewClone:GetBoundingBox()
	local cameraDistance = math.max(boundsSize.X, boundsSize.Y + 0.3, boundsSize.Z) * 1.7 + 1.25
	local cameraFocus = Vector3.new(0, boundsSize.Y * 0.1, 0)
	self.PreviewCamera.CFrame = CFrame.new(Vector3.new(0, cameraFocus.Y, cameraDistance), cameraFocus)
		* CFrame.new(previewCameraOffset)

	self.previewConnection = RunService.RenderStepped:Connect(function(deltaTime)
		if not self.alive or not self.previewModel or not self.previewBasePivot then
			return
		end

		self.previewAngle += deltaTime * 0.6
		self.previewModel:PivotTo(self.previewBasePivot * CFrame.fromAxisAngle(previewModelSpinAxis, self.previewAngle))
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
		local gunInfo = InvokeLogger.invokeServer(GetGunSettings, weaponInfo.Name) :: GunInfo
		if not gunInfo then
			warn("No gun info", weaponInfo.Name)
			return
		end

		local info = weaponInfo.ItemInfo
		local damageType = info.DamageType

		-- replace info with new gun info
		weaponInfo.ItemInfo = gunInfo

		local damageScore = GunScoring.getDamageScore(gunInfo)
		local rateScore = GunScoring.getRateScore(gunInfo)
		local handleScore = GunScoring.getHandleScore(gunInfo)
		local clipScore = GunScoring.getClipScore(gunInfo)
		local zoomScore = GunScoring.getZoomScore(gunInfo)

		-- score 0 -> 1, 1 being amazing
		createBar("DMG", damageScore)
		createBar("RATE", rateScore)
		createBar("HANDLE", handleScore)
		createBar("CLIP", clipScore)
		createBar("ZOOM", zoomScore)

		local damageColor = DAMAGE_TYPE_TO_COLOR[damageType] or Color3.new(1, 1, 0)
		createPill(damageType, damageColor)
	elseif weaponInfo.Category == "Melee" then
		local meleeInfo = InvokeLogger.invokeServer(GetMeleeSettings, weaponInfo.Name) :: MeleeInfo
		if not meleeInfo then
			warn("No melee info", weaponInfo.Name)
			return
		end

		warn(meleeInfo)
		weaponInfo.ItemInfo = meleeInfo

		local damageScore = MeleeScoring.getDamageScore(meleeInfo)
		local speedScore = MeleeScoring.getSpeedScore(meleeInfo)
		local knockbackScore = MeleeScoring.getKnockbackScore(meleeInfo)
		local reliabilityScore = MeleeScoring.getReliabilityScore(meleeInfo)

		createBar("DMG", damageScore)
		createBar("SPEED", speedScore)
		createBar("KNOCK", knockbackScore)
		createBar("RELIAB", reliabilityScore)
	end

	for _, pill: Pill in ipairs(weaponInfo.Pills) do
		createPill(pill.Text, pill.Color)
	end
end

function ShopUI:SelectWeapon(weaponName: string)
	if self.purchaseInProgress then
		warn("Can't select weapon while purchase is in progress")
		self:PlaySound("Error")
		return
	end

	-- mass-spamming can cause strange happenings
	if self.selectInProgress then
		return
	end

	local weaponInfo = _getWeaponInfo(weaponName) :: WeaponInfo
	if not weaponInfo then
		warn("No weapon info", weaponName)
		return
	end

	self.selectInProgress = true

	self.currentWeaponName = weaponName

	self.LoreBox.TextLabel.Text = weaponInfo.Lore
	self.WeaponInfo.WeaponTitle.Text = weaponInfo.Name
	self.WeaponStats.SpecialText.Text = weaponInfo.SpecialText
	self:ApplySelectedWeaponState(weaponInfo)

	self:SetupWeaponPreview(weaponName)
	self:LoadStats(weaponInfo)

	task.delay(0.3, function()
		self.selectInProgress = false
	end)
end

function ShopUI:SelectFilter(filterType: "Weight", filter)
	if self.currentFilterName == filter then
		return
	end

	self.currentFilter = filter
	self.currentFilterName = filter

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

function ShopUI:SelectFilterByIndex(selectionIndex: number)
	local filterInfo = self.filterInfos[selectionIndex]
	if not filterInfo then
		return
	end

	if self.currentFilterIndex == selectionIndex then
		return
	end

	self.currentFilterIndex = selectionIndex
	self:SelectFilter(filterInfo.FilterType, filterInfo.Name)

	for index, filterFrame in ipairs(self.filterFrames) do
		local imageButton = filterFrame:FindFirstChild("ImageButton")
		if imageButton and imageButton:IsA("ImageButton") then
			imageButton.ImageColor3 = if index == selectionIndex
				then Color3.new(0.533333, 0.533333, 0.533333)
				else Color3.new(1, 1, 1)
		end
	end
end

function ShopUI:UpdateWeaponInfos()
	for _, infoFrame in ipairs(self.currentWeaponInfoButtons) do
		local title = infoFrame.Title :: TextLabel
		local weaponName = title.Text
		local weaponInfo = _getWeaponInfo(weaponName) :: WeaponInfo
		if not weaponInfo then
			warn("No weapon info", weaponName)
			continue
		end

		self:ApplyWeaponFrameState(infoFrame, weaponInfo)
	end
end

function ShopUI:LoadWeaponInfos(info: { WeaponInfo })
	local selectionReference = self.ScrollingFrame.Reference
	self.currentWeaponInfoButtons = {}

	-- remove existing frames
	for _, child in ipairs(self.ScrollingFrame:GetChildren()) do
		if child:IsA("TextButton") and child.Name ~= "Reference" then
			child:Destroy()
		end
	end

	for _, weaponInfo: WeaponInfo in ipairs(info) do
		local weaponTextButton = selectionReference:Clone() :: TextButton
		weaponTextButton.Visible = true
		table.insert(self.currentWeaponInfoButtons, weaponTextButton)

		local DisplayImage = weaponTextButton.ImageLabel :: ImageLabel
		local Cost = weaponTextButton.Cost :: TextLabel
		local Level = weaponTextButton.Level :: TextLabel
		local Title = weaponTextButton.Title :: TextLabel
		weaponTextButton.Name = weaponInfo.Name

		DisplayImage.Image = weaponInfo.PreviewImage
		Title.Text = weaponInfo.Name
		Level.Text = "LVL " .. formatNumber(weaponInfo.Level)
		Cost.Text = "※ " .. formatNumber(weaponInfo.Price)
		weaponTextButton.Parent = self.ScrollingFrame

		self:ApplyWeaponFrameState(weaponTextButton, weaponInfo)

		weaponTextButton.MouseButton1Down:Connect(function()
			self:SelectWeapon(weaponInfo.Name)
		end)

		self:HookBaseButtonSounds(weaponTextButton, 0.04)
	end
end

function ShopUI:LoadFilters()
	local filterReference = self.Filters.FilterReference
	local sortedFilters = {}
	for _, filter: FilterInfo in ipairs(self.shopInfo.Filters) do
		table.insert(sortedFilters, filter)
	end

	table.sort(sortedFilters, function(left, right)
		return left.Order < right.Order
	end)

	self.filterFrames = {}
	self.filterInfos = sortedFilters

	for index, filter: FilterInfo in ipairs(sortedFilters) do
		local filterFrame = filterReference:Clone()
		local selectionButton = filterFrame:WaitForChild("ImageButton") :: ImageButton
		selectionButton.Image = filter.Image
		filterFrame:SetAttribute("SelectionNumber", index)
		filterFrame:SetAttribute("FilterName", filter.Name)

		filterFrame.Name = filter.Name
		filterFrame.LayoutOrder = index
		filterFrame.Visible = true
		filterFrame.Parent = self.Filters
		table.insert(self.filterFrames, filterFrame)

		selectionButton.MouseButton1Down:Connect(function()
			self:SelectFilterByIndex(index)
		end)
	end

	if #sortedFilters > 0 then
		self:SelectFilterByIndex(1)
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

function ShopUI:PurchaseCurrentItem()
	if not self.alive then
		return
	end

	local selectedWeaponName = self.currentWeaponName or self.WeaponInfo.WeaponTitle.Text
	local weaponInfo = _getWeaponInfo(selectedWeaponName)
	if not weaponInfo then
		warn("No weapon info for", selectedWeaponName)
		return
	end

	local isOwned = self:OwnsWeapon(selectedWeaponName)
	if isOwned then
		warn("Purchase failed:", "Already owned")
		self:PlaySound("Error")
		return
	end

	-- We can initially validate it ourselves
	local requirementLockState = getRequirementLockState(weaponInfo)
	if not requirementLockState.isUnlocked then
		warn("Purchase failed:", requirementLockState.lockText)
		self:PlaySound("Error")
		return
	end

	-- We can initially validate it ourselves
	local result = shouldBeLocked(weaponInfo.Level, weaponInfo.Price)
	if not result["isUnlocked"] then
		warn("Purchase failed:", "Not unlocked")
		self:PlaySound("Error")
		return
	end

	if self.purchaseInProgress then
		warn("Purchase failed:", "Already purchasing")
		self:PlaySound("Error")
		return
	end

	self.purchaseLoadingToken += 1
	local purchaseLoadingToken = self.purchaseLoadingToken

	local function endPurchase()
		self.PurchaseButton.BackgroundColor3 = Color3.new(1, 1, 1)
		self.purchaseInProgress = false
		self.purchaseLoadingToken += 1
		self:ExitLoadingState()

		local pendingWeaponName = self.pendingPurchaseRefreshWeaponName or selectedWeaponName
		self:RefreshPurchasedWeaponState(pendingWeaponName)
	end

	self.PurchaseButton.BackgroundColor3 = Color3.new(0.4, 0.4, 0.4)
	self.purchaseInProgress = true

	task.delay(PURCHASE_LOADING_DELAY, function()
		if not self.purchaseInProgress then
			return
		end

		if self.purchaseLoadingToken ~= purchaseLoadingToken then
			return
		end

		self:StartLoadingState()
	end)

	-- Our own validation passed, let's see if the server agrees
	local success, message = InvokeLogger.invokeServer(Remotes.RequestPurchase, selectedWeaponName)
	if not success then
		warn("Purchase failed:", message)
		self:PlaySound("Error")
		endPurchase()
		return
	end

	self:PlaySound("Purchase")
	endPurchase()
end

function ShopUI:InitButtons()
	local function moveFilter(offset: number)
		local nextIndex = math.clamp(self.currentFilterIndex + offset, 1, #self.filterInfos)
		self:SelectFilterByIndex(nextIndex)
	end

	self.LeftFilter.MouseButton1Down:Connect(function()
		moveFilter(-1)
	end)

	self.RightFilter.MouseButton1Down:Connect(function()
		moveFilter(1)
	end)

	for _, desc in ipairs(self.MainFrame:GetDescendants()) do
		if desc:IsA("TextButton") or desc:IsA("ImageButton") then
			self:HookBaseButtonSounds(desc)
		end
	end

	self.PurchaseButton.MouseButton1Down:Connect(function()
		self:PurchaseCurrentItem()
	end)
end

function ShopUI:InitLoadingScreen()
	local rotationTween = TweenService:Create(
		self.LoadingIcon,
		TweenInfo.new(0.4, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, -1),
		{ Rotation = 360 }
	)
	rotationTween:Play()
end

function ShopUI:Init()
	self:UpdateCurrencyDisplay(getCurrentMoney())
	self.MainFrame.Level.Text = "LVL " .. formatNumber(getCurrentLevel())
	self:LoadFilters()
	self:LoadSounds()
	self:InitButtons()
	self:InitLoadingScreen()
	self:SetupRenderConnect()
	self:ListenForPurchase()
	self:UpdateOwnedWeapons()
	self:Show(true)

	_getAllWeaponInfosForCategory(self.shopInfo.Category)
	self:SelectFilterByIndex(1)
end

function ShopUI:ListenForPurchase()
	if self.purchaseConnection then
		self.purchaseConnection:Disconnect()
	end

	if self.currencyConnection then
		self.currencyConnection:Disconnect()
	end

	local leaderstats = Player:WaitForChild("leaderstats")
	local credits = leaderstats:WaitForChild("Credits") :: NumberValue
	-- self.currencyConnection = credits:GetPropertyChangedSignal("Value"):Connect(function()
	-- 	self:UpdateCurrencyDisplay(credits.Value)
	-- end)

	self.purchaseConnection = Remotes.ItemPurchased.OnClientEvent:Connect(function(weaponName)
		self:RefreshPurchasedWeaponState(weaponName)
		self:UpdateCurrencyDisplay(credits.Value)
	end)
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

function ShopUI:DisableEnabledCoreGuis()
	self.enabledCoreGuis = getEnabledCoreGuis()

	for _, coreGuiType in ipairs(self.enabledCoreGuis) do
		if coreGuiType == Enum.CoreGuiType.ExperienceShop then
			continue
		end

		pcall(function()
			StarterGui:SetCoreGuiEnabled(coreGuiType, false)
		end)
	end
end

function ShopUI:RestoreCoreGuis()
	if not self.enabledCoreGuis then
		return
	end

	for _, coreGuiType in ipairs(self.enabledCoreGuis) do
		if coreGuiType == Enum.CoreGuiType.ExperienceShop then
			continue
		end
		pcall(function()
			StarterGui:SetCoreGuiEnabled(coreGuiType, true)
		end)
	end

	self.enabledCoreGuis = nil
end

function ShopUI:UnlockCharacter()
	if self.characterDiedConnection then
		self.characterDiedConnection:Disconnect()
		self.characterDiedConnection = nil
	end

	if self.characterAddedConnection then
		self.characterAddedConnection:Disconnect()
		self.characterAddedConnection = nil
	end

	if self.lockedRootPart and self.lockedRootPart.Parent and self.originalRootAnchored ~= nil then
		self.lockedRootPart.Anchored = self.originalRootAnchored
	end

	if self.lockedHumanoid and self.lockedHumanoid.Parent then
		if self.originalWalkSpeed ~= nil then
			self.lockedHumanoid.WalkSpeed = self.originalWalkSpeed
		end

		if self.originalJumpPower ~= nil then
			self.lockedHumanoid.JumpPower = self.originalJumpPower
		end

		if self.originalJumpHeight ~= nil then
			self.lockedHumanoid.JumpHeight = self.originalJumpHeight
		end

		if self.originalAutoRotate ~= nil then
			self.lockedHumanoid.AutoRotate = self.originalAutoRotate
		end
	end

	self.lockedCharacter = nil
	self.lockedHumanoid = nil
	self.lockedRootPart = nil
	self.originalWalkSpeed = nil
	self.originalJumpPower = nil
	self.originalJumpHeight = nil
	self.originalAutoRotate = nil
	self.originalRootAnchored = nil
end

function ShopUI:LockCharacter()
	self:UnlockCharacter()

	local character = Player.Character
	if not character then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local rootPart = character:FindFirstChild("HumanoidRootPart")

	if not humanoid or not rootPart then
		return
	end

	self.lockedCharacter = character
	self.lockedHumanoid = humanoid
	self.lockedRootPart = rootPart
	self.originalWalkSpeed = humanoid.WalkSpeed
	self.originalJumpPower = humanoid.JumpPower
	self.originalJumpHeight = humanoid.JumpHeight
	self.originalAutoRotate = humanoid.AutoRotate
	self.originalRootAnchored = rootPart.Anchored

	rootPart.Anchored = true
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	humanoid.JumpHeight = 0
	humanoid.AutoRotate = false

	self.characterDiedConnection = humanoid.Died:Connect(function()
		if self.alive then
			self:Hide(true)
		end
	end)

	self.characterAddedConnection = Player.CharacterAdded:Connect(function(newCharacter)
		if not self.alive then
			return
		end

		if newCharacter ~= self.lockedCharacter then
			self:Hide(true)
		end
	end)
end

function ShopUI:Show(entering: boolean)
	self.alive = true

	if entering then
		self:DisableEnabledCoreGuis()
		lockCamera()
		self.baseCameraCFrame = self.CameraPart.CFrame
		tweenCameraCFrame(self.CameraPart.CFrame)

		Player:SetAttribute("InShop", true)
		self:LockCharacter()
	end

	self:TweenBlur(24)
	self:TweenTintColor(Color3.new(0.647059, 0.647059, 0.647059))

	local main = self.MainFrame :: Frame
	main:TweenPosition(UDim2.new(0.5, 0, 0.5, 0), Enum.EasingDirection.Out, Enum.EasingStyle.Quint, 1.5, true)
	self:UpdateOwnedWeapons()
	self:UpdateWeaponInfos()
end

function ShopUI:Hide(exitting: boolean, destroyAfterFade: boolean?)
	if not self.alive and not exitting then
		return
	end

	self.alive = false
	local main = self.MainFrame :: Frame

	self:UnlockCharacter()
	self:RestoreCoreGuis()

	if exitting then
		returnCamera()
		Player:SetAttribute("InShop", false)
	end

	self:TweenBlur(0)
	self:TweenTintColor(Color3.new(1, 1, 1))

	main:TweenPosition(UDim2.new(0.5, 0, 2, 0), Enum.EasingDirection.Out, Enum.EasingStyle.Quint, 1, true, function()
		if exitting and (destroyAfterFade == nil or destroyAfterFade) then
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

	if self.purchaseConnection then
		self.purchaseConnection:Disconnect()
		self.purchaseConnection = nil
	end

	if self.currencyConnection then
		self.currencyConnection:Disconnect()
		self.currencyConnection = nil
	end

	if self.characterAddedConnection then
		self.characterAddedConnection:Disconnect()
		self.characterAddedConnection = nil
	end

	if self.characterDiedConnection then
		self.characterDiedConnection:Disconnect()
		self.characterDiedConnection = nil
	end

	self.currencyAnimationToken += 1
	self:RestoreCoreGuis()
	self:UnlockCharacter()

	self.blurEffect:Destroy()
	self.colorCorrection:Destroy()
	self.gui:Destroy()

	for _, sound in pairs(self.sounds) do
		sound:Destroy()
	end
end

return ShopUI
