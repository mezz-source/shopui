local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local StarterGui = game:GetService("StarterGui")

local Player = Players.LocalPlayer
local GUIs = ReplicatedStorage:WaitForChild("GUIs")

local ShopUI = require(ReplicatedStorage.ShopClient.UI.Shop)
local LoadoutUI = require(ReplicatedStorage.ShopClient.UI.Loadout)
local StatsUI = require(ReplicatedStorage.ShopClient.UI.Stats)

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
	self.main.OptionsMain.Position = UDim2.new(0.5, 0, -2, 0)

	self.shop = ShopUI.new(self.shopModelName, {
		gui = self.shopMain,
		autoStart = false,
		onExitRequested = function()
			self:RequestClose()
		end,
	})
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
	setVisible(self.shopMain, false)
	setVisible(self.statsMain, false)
	self:LoadSounds()

	self:bindButton(self.optionsMain, "Loadout", function()
		self:SetState("Loadout")
	end)
	self:bindButton(self.optionsMain, "Shop", function()
		self:SetState("Shop")
	end)
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

	showCoreGui()
	self.destroyed = true
	self.closing = true

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

	if self.gui and self.gui.Parent then
		self.gui:Destroy()
	end

	Player:SetAttribute("InShop", false)
end

return SLSGui
