local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local StarterGui = game:GetService("StarterGui")

local Player = Players.LocalPlayer
local GUIs = ReplicatedStorage:WaitForChild("GUIs")

local ShopUI = require(ReplicatedStorage.ShopClient.UI.Shop)
local LoadoutUI = require(ReplicatedStorage.ShopClient.UI.Loadout)
local StatsUI = require(ReplicatedStorage.ShopClient.UI.Stats)
local AdaptiveMusic = require(ReplicatedStorage.AdaptiveMusic.AdaptiveSong)
local ShopTypes = require(ReplicatedStorage.ShopClient.ShopTypes)
local InvokeLogger = require(ReplicatedStorage.ShopClient.InvokeLogger)

local Remotes = ReplicatedStorage:WaitForChild("ShopRemotes")
local RemoteInfoAll = Remotes:WaitForChild("GetAllInfoForCategory")
local GetGunSettings = Remotes:WaitForChild("GetGunSettings")
local GetMeleeSettings = Remotes:WaitForChild("GetMeleeSettings")

local SLSGui = {}
SLSGui.__index = SLSGui

local SOUND_MAP = {
	Select = { SoundId = "rbxassetid://124033101073224" },
	Hover = { SoundId = "rbxassetid://139295675611093" },
	EndHover = { SoundId = "rbxassetid://139295675611093", PlaybackSpeed = 0.8, Volume = 0.3 },
	Error = { SoundId = "rbxassetid://8466981206" },
	Equip = { SoundId = "rbxassetid://128178943908896" },
	Expand = { SoundId = "rbxassetid://139246456147301" },
	Unequip = { SoundId = "rbxassetid://128178943908896", PlaybackSpeed = 0.8, Volume = 0.3 },
}

type SLSState = "Shop" | "Loadout" | "Stats"

type SLSGuiOptions = {
	shopModelName: string?,
	startState: SLSState?,
}

local CLOSE_FADE_DURATION = 1

local staticWeaponInfos: { [string]: ShopTypes.WeaponInfo } = {}
local staticGunSettings: { [string]: ShopTypes.GunSettings } = {}
local staticMeleeSettings: { [string]: ShopTypes.MeleeInfo } = {}
local staticOwnedItems: { string } = {}
local staticLoadComplete = false

task.spawn(function()
	local allGunInfos = InvokeLogger.invokeServer(RemoteInfoAll, { category = "Gun" }) :: { ShopTypes.WeaponInfo }?
	local allMeleeInfos = InvokeLogger.invokeServer(RemoteInfoAll, { category = "Melee" }) :: { ShopTypes.WeaponInfo }?

	if allGunInfos then
		for _, info in ipairs(allGunInfos) do
			staticWeaponInfos[info.Name] = info
		end
	end

	if allMeleeInfos then
		for _, info in ipairs(allMeleeInfos) do
			staticWeaponInfos[info.Name] = info
		end
	end

	for name, info in pairs(staticWeaponInfos) do
		if info.Category == "Gun" then
			local settings = InvokeLogger.invokeServer(GetGunSettings, name) :: ShopTypes.GunSettings?
			if settings then
				staticGunSettings[name] = settings
			end
		elseif info.Category == "Melee" then
			local settings = InvokeLogger.invokeServer(GetMeleeSettings, name) :: ShopTypes.MeleeInfo?
			if settings then
				staticMeleeSettings[name] = settings
			end
		end
	end

	local ownedResult = InvokeLogger.invokeServer(Remotes:WaitForChild("GetOwnedItems"))
	if typeof(ownedResult) == "table" then
		staticOwnedItems = ownedResult
	end

	staticLoadComplete = true
end)

local function hideCoreGui()
	local success, err = pcall(function(...)
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, false)
	end)
	if not success then
		warn("Failed to hide CoreGui: " .. err)
	end
end

local function showCoreGui()
	local success, err = pcall(function(...)
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, true)
	end)
	if not success then
		warn("Failed to show CoreGui: " .. err)
	end
end

local function setVisible(instance: Instance?, visible: boolean)
	if instance and instance:IsA("GuiObject") then
		instance.Visible = visible
	end
end

local function fadeDescendant(instance: Instance, targetTransparency: number, tweenInfo: TweenInfo)
	local goals = {}

	if instance:IsA("CanvasGroup") then
		goals.GroupTransparency = targetTransparency
	end

	if instance:IsA("GuiObject") then
		goals.BackgroundTransparency = targetTransparency
	end

	if instance:IsA("ImageLabel") or instance:IsA("ImageButton") then
		goals.ImageTransparency = targetTransparency
	end

	if instance:IsA("TextLabel") or instance:IsA("TextButton") or instance:IsA("TextBox") then
		goals.TextTransparency = targetTransparency
		goals.TextStrokeTransparency = targetTransparency
	end

	if next(goals) then
		pcall(function()
			TweenService:Create(instance, tweenInfo, goals):Play()
		end)
	end
end

local function fadeTree(root: Instance, targetTransparency: number, duration: number)
	local tweenInfo = TweenInfo.new(duration, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
	fadeDescendant(root, targetTransparency, tweenInfo)

	for _, descendant in ipairs(root:GetDescendants()) do
		fadeDescendant(descendant, targetTransparency, tweenInfo)
	end
end

function SLSGui:bindButton(root: Instance, name: string, callback: () -> ())
	local button = root:FindFirstChild(name, true)
	if button and (button:IsA("TextButton") or button:IsA("ImageButton")) then
		self:HookBaseButtonSounds(button)
		button.MouseButton1Click:Connect(callback)
	end
end

function SLSGui:PlaySound(soundName: string)
	local sound = self.sounds[soundName]
	if not sound then
		warn(`No sound named {soundName} was found`)
		return
	end

	sound:Play()
end

function SLSGui:LoadSounds()
	for soundName, propertyList in pairs(SOUND_MAP) do
		local newSound = Instance.new("Sound", workspace)
		newSound.Name = soundName .. "UI"

		for propertName, _ in pairs(propertyList) do
			newSound[propertName] = propertyList[propertName]
		end

		self.sounds[soundName] = newSound
	end
end

function SLSGui.new(options: SLSGuiOptions?)
	local self = setmetatable({}, SLSGui)
	local gui = GUIs.SLSGui:Clone()
	gui.Parent = Player.PlayerGui

	self.gui = gui
	self.main = gui:WaitForChild("Main")
	self.optionsMain = self.main:WaitForChild("OptionsMain")
	self.loadoutMain = self.main:WaitForChild("LoadoutMain")
	self.shopMain = self.main:WaitForChild("ShopMain")
	self.statsMain = self.main:WaitForChild("StatsMain")
	self.started = false
	self.closing = false
	self.destroyed = false
	self.transitioning = false
	self.currentState = nil
	self.shopModelName = if options then options.shopModelName else nil
	self.startState = if options and options.startState then options.startState else "Shop"
	self.sounds = {}
	self.infoLibrary = nil
	self.main.OptionsMain.Position = UDim2.new(0.5, 0, -2, 0)

	self.song = AdaptiveMusic.new("RunningOnDeadTime", false)

	if self.shopModelName then
		self.shop = ShopUI.new(self.shopModelName, {
			gui = self.shopMain,
			autoStart = false,
			onExitRequested = function()
				self:RequestClose()
			end,
		})
	end
	self.loadout = LoadoutUI.new(self.loadoutMain, {
		onExitRequested = function()
			self:RequestClose()
		end,
	})
	self.stats = StatsUI.new(self.statsMain, {
		onExitRequested = function()
			self:RequestClose()
		end,
	})

	setVisible(self.optionsMain, true)
	setVisible(self.loadoutMain, false)
	setVisible(self.statsMain, false)
	self:LoadSounds()

	self:bindButton(self.optionsMain, "Loadout", function()
		local fadeTime = (120 / self.song.conductor.bpm) * 2
		self.song:ScheduleFadeInSections(2, "Leads", 0, fadeTime)
		self.song:ScheduleFadeInSections(2, "Chords", 0, fadeTime)
		self.song:ScheduleFadeInSections(2, "Backing", 0, fadeTime)
		self.song:ScheduleFadeInSections(2, "Bassline", 0.3, fadeTime)
		self.song:ScheduleFadeInSections(2, "Percussion", 0.5, fadeTime)

		self:SetState("Loadout")
	end)

	if self.shopModelName then
		setVisible(self.shopMain, false)

		self:bindButton(self.optionsMain, "Shop", function()
			local fadeTime = (120 / self.song.conductor.bpm) * 2
			self.song:ScheduleFadeInSections(1, "Leads", 0.5, fadeTime)
			self.song:ScheduleFadeInSections(1, "Chords", 0.5, fadeTime)
			self.song:ScheduleFadeInSections(1, "Backing", 0.5, fadeTime)
			self.song:ScheduleFadeInSections(1, "Bassline", 0.5, fadeTime)
			self.song:ScheduleFadeInSections(1, "Percussion", 0.5, fadeTime)

			self:SetState("Shop")
		end)
	else
		self.optionsMain.MenuOptions.Options.ShopFrame.Visible = false
	end

	self:bindButton(self.optionsMain, "Stats", function()
		self:SetState("Stats")
	end)

	return self
end

function SLSGui:HookBaseButtonSounds(button: TextButton | ImageButton, scaleModifierAmount: number?)
	local scaleModifier = button:FindFirstChild("UIScale") or Instance.new("UIScale", button)

	button.MouseEnter:Connect(function()
		TweenService:Create(
			scaleModifier,
			TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
			{ Scale = 1 + (scaleModifierAmount or 0.07) }
		):Play()

		self:PlaySound("Hover")
	end)

	button.MouseLeave:Connect(function()
		TweenService
			:Create(scaleModifier, TweenInfo.new(0.4, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { Scale = 1 })
			:Play()

		self:PlaySound("EndHover")
	end)
end

function SLSGui:CollectInfoLibrary(): ShopTypes.InfoLibrary
	while not staticLoadComplete do
		task.wait()
	end

	local library: ShopTypes.InfoLibrary = {}

	function library.getWeaponInfo(name: string): ShopTypes.WeaponInfo?
		return staticWeaponInfos[name]
	end

	function library.getAllForCategory(category: ShopTypes.Category): { ShopTypes.WeaponInfo }
		local result = {}
		for _, info in pairs(staticWeaponInfos) do
			if info.Category == category then
				table.insert(result, info)
			end
		end
		return result
	end

	function library.queryWeapons(
		category: ShopTypes.Category,
		weights: { ShopTypes.Weight }?
	): { ShopTypes.WeaponInfo }
		local result = {}
		for _, info in pairs(staticWeaponInfos) do
			if info.Category == category then
				if weights == nil or #weights == 0 then
					table.insert(result, info)
				else
					for _, w in ipairs(weights) do
						if info.Weight == w then
							table.insert(result, info)
							break
						end
					end
				end
			end
		end
		return result
	end

	function library.getGunSettings(name: string): ShopTypes.GunSettings?
		return staticGunSettings[name]
	end

	function library.getMeleeSettings(name: string): ShopTypes.MeleeInfo?
		return staticMeleeSettings[name]
	end

	function library.getOwnedItems(): { string }
		return table.clone(staticOwnedItems)
	end

	function library.isOwned(name: string): boolean
		return table.find(staticOwnedItems, name) ~= nil
	end

	function library.refreshOwnedItems(): { string }
		local result = InvokeLogger.invokeServer(Remotes:WaitForChild("GetOwnedItems"))
		if typeof(result) == "table" then
			staticOwnedItems = result
		end
		return table.clone(staticOwnedItems)
	end

	function library.registerOwnedItem(name: string)
		if table.find(staticOwnedItems, name) == nil then
			table.insert(staticOwnedItems, name)
		end
	end

	return library
end

function SLSGui:Start(initialState: SLSState?)
	if self.started then
		if initialState then
			self:SetState(initialState)
		end
		return
	end
	self.main.OptionsMain:TweenPosition(
		UDim2.new(0.5, 0, 0.5, 0),
		Enum.EasingDirection.Out,
		Enum.EasingStyle.Quint,
		1,
		true
	)

	local Character = Players.LocalPlayer.Character
	local Humanoid = Character:WaitForChild("Humanoid")
	Humanoid.Died:Once(function()
		warn("Character suddenly had a heart attacked and DIED mid shop.")
		self:Destroy()
		workspace.CurrentCamera.CameraType = Enum.CameraType.Custom
	end)

	-- disable reset
	local success, err = pcall(function(...)
		StarterGui:SetCore("ResetButtonCallBack", false)
	end)

	if not success then
		warn(err)
	end

	self.infoLibrary = self:CollectInfoLibrary()

	if self.shop then
		self.shop.infoLibrary = self.infoLibrary
	end
	self.loadout.infoLibrary = self.infoLibrary

	self.song:Play()

	hideCoreGui()

	self.started = true
	self.gui.Enabled = true
	Player:SetAttribute("InShop", true)
	self:SetState(initialState or self.startState)
end

function SLSGui:RequestClose()
	if self.closing or self.destroyed or self.transitioning then
		return
	end

	self.song:Stop()

	self.closing = true
	Player:SetAttribute("InShop", false)

	if self.currentState == "Shop" and self.shop then
		self.shop:Hide(true, false)
	elseif self.currentState == "Loadout" and self.loadout then
		self.loadout:Hide(true, false)
	elseif self.currentState == "Stats" and self.stats then
		self.stats:Hide()
	end

	self.main.Active = false
	fadeTree(self.main, 1, CLOSE_FADE_DURATION)

	task.delay(CLOSE_FADE_DURATION, function()
		self:Destroy()
	end)
end

function SLSGui:SetState(newState: SLSState)
	if self.closing or self.destroyed or self.transitioning then
		return
	end

	if self.currentState == newState then
		return
	end

	self.transitioning = true
	self:PlaySound("Select")

	local options = self.main.OptionsMain.MenuOptions.Options
	local targetFrame = options:FindFirstChild(newState .. "Frame")

	for _, frameOption in ipairs(options:GetChildren()) do
		if frameOption:IsA("Frame") then
			local Underline = frameOption:FindFirstChild("Underline")
			local Button = frameOption:FindFirstChildOfClass("TextButton")
			if Underline then
				Underline.BackgroundTransparency = if frameOption == targetFrame then 0 else 0.5
			end
			if Button then
				Button.TextTransparency = if frameOption == targetFrame then 0 else 0.5
			end
		end
	end

	if self.currentState == "Shop" and self.shop then
		self.shop:Hide(false)
	end

	if self.currentState == "Loadout" and self.loadout then
		self.loadout:Hide()
	end

	if self.currentState == "Stats" and self.stats then
		self.stats:Hide()
	end

	self.currentState = newState

	if newState == "Shop" then
		setVisible(self.shopMain, true)
		setVisible(self.loadoutMain, false)
		setVisible(self.statsMain, false)

		if self.shop then
			if self.shop.started then
				self.shop:Show(true)
			else
				self.shop:Start()
			end
		end
	elseif newState == "Loadout" then
		setVisible(self.shopMain, false)
		setVisible(self.loadoutMain, true)
		setVisible(self.statsMain, false)

		if self.loadout then
			self.loadout:Start()
			self.loadout:Show()
		end
	elseif newState == "Stats" then
		setVisible(self.shopMain, false)
		setVisible(self.loadoutMain, false)
		setVisible(self.statsMain, true)

		if self.stats then
			self.stats:Start()
			self.stats:Show()
		end
	end

	self.transitioning = false
	Player:SetAttribute("InShop", true)
end

function SLSGui:Hide()
	self:RequestClose()
end

function SLSGui:Destroy()
	if self.destroyed then
		return
	end

	-- disable reset
	local success, err = pcall(function(...)
		StarterGui:SetCore("ResetButtonCallBack", true)
	end)

	if not success then
		warn(err)
	end

	showCoreGui()
	self.destroyed = true
	self.closing = true
	self.song:Destroy()

	if self.shop then
		if self.currentState == "Shop" then
			self.shop:Hide(true, false)
		end
		self.shop:Destroy()
	end

	if self.loadout then
		self.loadout:Destroy()
	end

	if self.stats then
		self.stats:Destroy()
	end

	for _, sound in pairs(self.sounds) do
		sound:Destroy()
	end

	if self.gui and self.gui.Parent then
		self.gui:Destroy()
	end

	Player:SetAttribute("InShop", false)
end

return SLSGui
