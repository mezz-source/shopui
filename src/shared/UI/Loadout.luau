local LoadoutUI = {}
LoadoutUI.__index = LoadoutUI

type LoadoutUIOptions = {
	onExitRequested: (() -> ())?,
}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local LoadoutCharacterRef = ReplicatedStorage:WaitForChild("LoadoutCharacter") :: Folder
local Camera = workspace.CurrentCamera
local Player = Players.LocalPlayer

local Remotes = ReplicatedStorage:WaitForChild("ShopRemotes")
local RemoteInfo = Remotes:WaitForChild("GetWeaponInfo")
local LoadoutConfigs = script.Parent.Parent:WaitForChild("LoadoutConfigs")
local WeaponPreviews = ReplicatedStorage:WaitForChild("WeaponPreview")

local ShopTypes = require(ReplicatedStorage.ShopClient.ShopTypes)
local AnimationHandler = require(script.Parent.Parent.AnimationHandler)

local CAMERA_MOUSE_INFLUENCE = 0.24
local CAMERA_LERP_ALPHA = 0.01

type WeaponSlot = ShopTypes.WeaponSlot
type WeaponChoice = ShopTypes.WeaponChoice

local DarknessEffect = Camera:FindFirstChild("LoadoutDarkness") or Instance.new("ColorCorrectionEffect", Camera)
DarknessEffect.Name = "LoadoutDarkness"

export type LoadoutConfig = ShopTypes.LoadoutConfig

local SOUND_MAP = {
	Select = { SoundId = "rbxassetid://124033101073224" },
	Hover = { SoundId = "rbxassetid://139295675611093" },
	EndHover = { SoundId = "rbxassetid://139295675611093", PlaybackSpeed = 0.8, Volume = 0.3 },
	Error = { SoundId = "rbxassetid://8466981206" },
	Equip = { SoundId = "rbxassetid://128178943908896" },
	Expand = { SoundId = "rbxassetid://139246456147301" },
	Unequip = { SoundId = "rbxassetid://128178943908896", PlaybackSpeed = 0.8, Volume = 0.3 },
}

local WEIGHT_TO_IMAGE = {
	Light = "rbxassetid://107895193168900",
	Moderate = "rbxassetid://104459017965358",
	Heavy = "rbxassetid://110968118318707",
}

--[[

	UTILITY CAMERA/SCREEN FUNCTIONS

]]

local function lockCamera()
	Camera.CameraType = Enum.CameraType.Scriptable
end

local function returnCamera()
	Camera.CameraType = Enum.CameraType.Custom
end

local function fadeScreen(): Tween
	local darknessTween = TweenService:Create(DarknessEffect, TweenInfo.new(1), { Brightness = -2 })
	darknessTween:Play()
	return darknessTween
end

local function showScreen(): Tween
	local darknessTween = TweenService:Create(DarknessEffect, TweenInfo.new(1), { Brightness = 0 })
	darknessTween:Play()
	return darknessTween
end

--[[

	CHARACTER EQUIP/ANIMATION HANDLER

]]

local function getAnimsFromGunModel(model: Model): { ["Idle"]: number, ["Equip"]: number }
	local Setting = model:FindFirstChild("Setting")
	if not Setting then
		warn("Gun", model.Name, "is missing settings module")
		return { Idle = 0, Equip = 0 }
	end

	local module = require(Setting)
	return {
		Idle = tostring(module.IdleAnimationID or 0),
		Equip = tostring(module.EquippedAnimationID or 0),
	}
end

local function getAnimsFromMeleeModel(model: Model): { ["Idle"]: number, ["Equip"]: number }
	local Animations = model:FindFirstChild("Animations") :: Folder
	if not Animations then
		warn("Melee weapon", model.Name, "is missing animations")
		return { Idle = 0, Equip = 0 }
	end

	local Idle = Animations:WaitForChild("Idle") :: Animation
	local Equip = Animations:WaitForChild("Equip") :: Animation
	-- remove RBX asset from AnimatioNID
	local idleId = Idle.AnimationId:gsub("rbxassetid://", "")
	local equipId = Equip.AnimationId:gsub("rbxassetid://", "")

	return {
		Idle = idleId,
		Equip = equipId,
	}
end

function LoadoutUI:CharacterWeldWeapon(weaponModel: Model)
	local Base4 = weaponModel:FindFirstChild("4 - Base")
	local NotHandle = weaponModel:FindFirstChild("NotHandle")

	if Base4 then
		Base4.Anchored = false
		print("Base4")
		self.base4Weld.Part1 = Base4
		self.base4Weld.Part0 = self.characterRightArm
		self.base4Weld.C0 = CFrame.new(0, 0, 0)
		self.base4Weld.C1 = CFrame.new(0, 0, 0)
	end

	if NotHandle then
		NotHandle.Anchored = false
		print("NotHandle")
		self.notHandleWeld.Part1 = NotHandle
		self.notHandleWeld.Part0 = self.characterRightArm
		self.notHandleWeld.C0 = CFrame.new(0, 0, 0)
		self.notHandleWeld.C1 = CFrame.new(0, 0, 0)
	end

	-- If neither special parts exist, try to weld the regular Handle
	if not Base4 and not NotHandle then
		print("Neither Base4 nor NotHandle found, trying to weld Handle")
		local Handle = weaponModel:FindFirstChild("Handle")

		if Handle then
			Handle.Anchored = false
			print("Handle")
			-- Use an existing handleWeld if present, otherwise fall back to base4Weld
			local weld = self.rightGrip
			weld.Part1 = Handle
			weld.Part0 = self.characterRightArm

			local GripCFrame = weaponModel:GetAttribute("GripCFrame") or CFrame.new(0, 0, 0)
			weld.C1 = GripCFrame
		end
	end
end

function LoadoutUI:CharacterPlayToolAnims(weaponModel: Model)
	local isGun = weaponModel:FindFirstChild("Setting") ~= nil

	local success, result = pcall(function()
		if isGun then
			return getAnimsFromGunModel(weaponModel)
		else
			return getAnimsFromMeleeModel(weaponModel)
		end
	end)

	if not success then
		warn("Failed to get animations for weapon model", weaponModel.Name, result)
		return
	end

	-- Check to make sure results are numbers
	if typeof(result) ~= "table" or typeof(result.Equip) ~= "string" or typeof(result.Idle) ~= "string" then
		warn(result)
		warn("Failed to load animations for weapon model", weaponModel.Name, "invalid animation ids")
		return
	end

	local equip = self.animationHandler:LoadAnimationById(result.Equip, "Equip")
	local idle = self.animationHandler:LoadAnimationById(result.Idle, "ToolIdle")
	idle.Looped = true
	equip.Priority = Enum.AnimationPriority.Action
	equip:Play(0.3)

	equip.Stopped:Connect(function()
		if idle and equip and self.currentWeaponModel == weaponModel then
			idle:Play()
		end
	end)
end

function LoadoutUI:CharacterClearLastTool()
	self.animationHandler:UnloadAll()
	if self.currentWeaponModel then
		self.currentWeaponModel:Destroy()
		self.currentWeaponModel = nil
	end
end

function LoadoutUI:CharacterEquipTool(toolName: string)
	-- Get the weapon model
	local model = WeaponPreviews:FindFirstChild(toolName)
	if not model then
		warn(`No weapon model found for {toolName}`)
		return
	end

	self:CharacterClearLastTool()

	local clone = model:Clone()
	self.currentWeaponModel = clone
	clone.Parent = self.characterModel

	self:CharacterWeldWeapon(clone)
	self:CharacterPlayToolAnims(clone)
end

--[[

	SOUND SYSTEM

]]

function LoadoutUI:PlaySound(soundName: string)
	local sound = self.sounds[soundName]
	if not sound then
		warn(`No sound named {soundName} was found`)
		return
	end

	sound:Play()
end

--[[

	BASIC BUTTON FEATURES

]]

function LoadoutUI:HookBaseButtonSounds(button: TextButton | ImageButton, scaleModifierAmount: number?)
	local scaleModifier = button:FindFirstChild("UIScale") or Instance.new("UIScale", button)

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

--[[

	INIT & CONFIG SETUP

]]

local function getLoadoutConfig(): LoadoutConfig
	local gamemode = workspace:GetAttribute("Gamemode")

	if gamemode == "Sandbox" then
		return require(LoadoutConfigs.Sandbox)
	else
		return require(LoadoutConfigs.Survival)
	end
end

function LoadoutUI.new(loadoutGui: Instance?, options: LoadoutUIOptions?)
	local self = setmetatable({}, LoadoutUI)
	self.mainFrame = loadoutGui
	self.started = false
	self.weaponSelectionVisible = false
	self.onExitRequested = if options then options.onExitRequested else nil
	self.exitButton = nil
	self.isShowing = false
	self.alive = true
	self.loadoutCharacter = LoadoutCharacterRef:Clone()
	self.loadoutCharacter.Parent = workspace
	self.loadoutConfig = getLoadoutConfig()
	self.sounds = {}
	self.weaponSlots = {}
	self.ownedItems = {}
	self.weaponChoices = {}

	-- TODO: Integrate filtering
	self.validWeights = { "Light", "Moderate", "Heavy" }
	self.searchName = ""

	self.lastSelectedSlot = nil

	local Character = self.loadoutCharacter:WaitForChild("Character")
	local CameraPart = self.loadoutCharacter:WaitForChild("CameraPart")
	local Humanoid = Character:WaitForChild("Humanoid")
	local Animator = Humanoid:WaitForChild("Animator")
	self.animator = Animator
	self.characterModel = Character

	self.animationHandler = AnimationHandler.new(Character)

	self.CameraPart = CameraPart
	self.baseCameraCFrame = CameraPart.CFrame

	if self.mainFrame then
		self.mainFrame.Visible = false
		local exitButton = self.mainFrame:FindFirstChild("Exit", true)
		if exitButton and exitButton:IsA("TextButton") then
			self.exitButton = exitButton
			exitButton.MouseButton1Down:Connect(function()
				self:RequestExit()
			end)
		end
	end

	self:Init()

	return self
end

function LoadoutUI:Init()
	self:LoadSounds()
	self:InitCharacter()
	self:InitButtons()

	self:InitFrameInstances()
	self:InitConfigSlots()
end

function LoadoutUI:InitFrameInstances()
	-- getting some basic GUI elements we're gonna need later
	local UIFrame = self.mainFrame:WaitForChild("UI")
	local WeaponSelection = UIFrame:WaitForChild("WeaponSelection")
	local SearchArea = WeaponSelection:WaitForChild("SearchArea")
	local WeightFilters = WeaponSelection:WaitForChild("WeightFilters")
	local WeightBar = UIFrame:WaitForChild("WeightBar")

	local SearchTextBox = SearchArea:WaitForChild("TextBox") :: TextBox
	SearchTextBox:GetPropertyChangedSignal("Text"):Connect(function()
		self.searchName = SearchTextBox.Text
		self:UpdateWeaponSelection()
	end)

	for _, child in ipairs(WeightFilters:getChildren()) do
		if child:IsA("ImageButton") and child:HasTag("Weight") then
			child.MouseButton1Down:Connect(function()
				local isSelected = child.BackgroundTransparency == 0
				self:SetWeightSelected(child, not isSelected)
				self:UpdateWeaponSelection()
			end)
		end
	end

	local WeaponSlots = UIFrame:WaitForChild("WeaponSlots")
	-- local LoadoutArea = UIFrame:WaitForChild("LoadoutArea")
	-- local WeightBar = UIFrame:WaitForChild("WeightBar")

	self.searchBox = SearchTextBox
	self.weaponSlotsUI = WeaponSlots
	self.weaponSelection = WeaponSelection
	self.weightBar = WeightBar
end

function LoadoutUI:InitConfigSlots()
	-- Create appropiate slots
	local config = self.loadoutConfig :: LoadoutConfig
	local slotReference = self.weaponSlotsUI:WaitForChild("Reference")

	for i = 1, config.maxSlots do
		local newSlot = slotReference:Clone()
		newSlot.Name = `Slot{i}`
		newSlot.Visible = true
		newSlot.Parent = self.weaponSlotsUI
		self:HookBaseButtonSounds(newSlot)

		local slot = {
			CurrentItem = "None",
			SlotIndex = i,
			Button = newSlot,
		}

		self.weaponSlots[i] = slot

		local function unequip()
			if slot.CurrentItem == "None" then
				return
			end

			self:PlaySound("Unequip")
			self:UnequipWeaponFromSlot(i)

			-- Close weapon selection when they clicked OUR slot while viewing weapons
			if self.weaponSelectionVisible and self.lastSelectedSlot == slot then
				self.weaponSelection.Visible = false
				self:HideWeaponSelection()
				self:SetSlotSelected(slot, false)
			end

			-- update the available weapons
			self:UpdateWeaponSelection()
		end

		local timeLastClicked = 0
		newSlot.MouseButton1Down:Connect(function()
			if not self.alive then
				return
			end

			-- Unequip on double clicking slots
			local now = tick()
			if now - timeLastClicked < 0.2 and slot.CurrentItem ~= "None" then
				unequip()
				timeLastClicked = now
				return
			end

			timeLastClicked = now

			self:SlotSelected(i)
		end)

		newSlot.MouseButton2Down:Connect(function()
			unequip()
		end)
	end
end

function LoadoutUI:InitButtons()
	for _, desc in ipairs(self.mainFrame:GetDescendants()) do
		if desc:IsA("TextButton") or desc:IsA("ImageButton") then
			print(desc.Name)
			self:HookBaseButtonSounds(desc)
		end
	end
end

function LoadoutUI:InitCharacter()
	self:LoadCharacterDescription()

	local RightArm = self.characterModel:WaitForChild("Right Arm")
	self.characterRightArm = RightArm

	local Base4Weld = Instance.new("Motor6D", RightArm)
	Base4Weld.Name = "4 - Base"
	Base4Weld.Part0 = RightArm
	self.base4Weld = Base4Weld

	local NotHandle = Instance.new("Motor6D", RightArm)
	NotHandle.Name = "NotHandle"
	NotHandle.Part0 = RightArm
	self.notHandleWeld = NotHandle

	local RightGrip = Instance.new("Weld", RightArm)
	RightGrip.Name = "RightGrip"
	self.rightGrip = RightGrip

	local position = Vector3.new(0, -1, 0)
	local orientation = Vector3.new(-90, 0, 0)
	RightGrip.C0 = CFrame.new(position)
		* CFrame.Angles(math.rad(orientation.X), math.rad(orientation.Y), math.rad(orientation.Z))
	RightGrip.Part0 = RightArm

	local idle = self.animationHandler:LoadAnimationById("180435571", "Idle") :: AnimationTrack
	idle.Looped = true
	idle:Play()
end

function LoadoutUI:LoadSounds()
	for soundName, propertyList in pairs(SOUND_MAP) do
		local newSound = Instance.new("Sound", workspace)
		newSound.Name = soundName .. "UI"

		for propertName, _ in pairs(propertyList) do
			newSound[propertName] = propertyList[propertName]
		end

		self.sounds[soundName] = newSound
	end
end

function LoadoutUI:LoadCharacterDescription()
	if not self.characterModel then
		return
	end
	local success, err = pcall(function()
		local desc = Players:GetHumanoidDescriptionFromUserIdAsync(Player.UserId)
		self.characterModel.Humanoid:ApplyDescription(desc)
	end)

	if not success then
		warn("Failed to load character description: " .. err)
	end
end

function LoadoutUI:SetupRenderConnect()
	if self.connection then
		self.connection:Disconnect()
	end

	self.connection = RunService.RenderStepped:Connect(function()
		if Camera.CameraType ~= Enum.CameraType.Scriptable then
			return
		end

		local mouse = UserInputService:GetMouseLocation()
		local viewportSize = Camera.ViewportSize
		local normalizedX = ((mouse.X / viewportSize.X) - 0.5) * 2
		local normalizedY = ((mouse.Y / viewportSize.Y) - 0.5) * 2

		local rightOffset = normalizedX * CAMERA_MOUSE_INFLUENCE
		local upOffset = -normalizedY * CAMERA_MOUSE_INFLUENCE

		local targetCFrame = self.baseCameraCFrame * CFrame.new(rightOffset, upOffset, 0)
		Camera.CFrame = Camera.CFrame:Lerp(targetCFrame, CAMERA_LERP_ALPHA)
	end)
end

--[[

	WEAPON EQUIP/DEQUIP PIPELINE

]]

function LoadoutUI:UnequipWeaponFromSlot(slotIndex: number)
	local slot = self.weaponSlots[slotIndex] :: WeaponSlot
	if not slot then
		warn(`No slot found for index {slotIndex}`, self.weaponSlots)
		return
	end

	self:NewWeaponUnequipped(slotIndex)
	self:ClearWeaponInSlot(slotIndex)
	self:UpdateWeightBar()
end

function LoadoutUI:EquipWeaponToSlot(weaponChoice: WeaponChoice, slotIndex: number): (boolean, string?)
	local slot = self.weaponSlots[slotIndex] :: WeaponSlot
	if not slot then
		warn(`No slot found for index {slotIndex}`, self.weaponSlots)
		return false, "Missing"
	end

	local canEquip = self:CanEquipWeaponInSlot(weaponChoice, slotIndex)
	if not canEquip then
		self:FlashWeightBar()
		return false, "Weight exceeded"
	end

	self:NewWeaponEquipped(weaponChoice, slotIndex)
	self:SetSlotSelected(self.lastSelectedSlot, false)
	self.lastSelectedSlot = nil

	local existingSlot = self:GetSlotWithWeaponName(weaponChoice.Name)
	if existingSlot then
		self:ClearWeaponInSlot(existingSlot.SlotIndex)
	end

	local Button = slot.Button
	local WeaponImage = Button:FindFirstChild("WeaponImage") :: ImageLabel
	local Title = Button:FindFirstChild("Title") :: TextLabel
	local EmptyText = Button:FindFirstChild("EmptyText") :: TextLabel
	EmptyText.Text = ""

	WeaponImage.Image = weaponChoice.PreviewImage
	WeaponImage.ImageTransparency = 0
	Title.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	Title.Text = weaponChoice.Name
	slot.CurrentItem = weaponChoice.Name
	slot.Weight = weaponChoice.Weight
	self:UpdateWeightBar()

	return true, "Success"
end

-- new equip effects
-- only use sounds for buttons
function LoadoutUI:NewWeaponEquipped(weaponChoice: WeaponChoice, slotIndex: number)
	-- effects
	local toolName = weaponChoice.Name
	self:CharacterEquipTool(toolName)
	self.lastEquippedChoice = weaponChoice.Name
end

-- new unequip effects
-- only use sounds for buttons
function LoadoutUI:NewWeaponUnequipped(slotIndex: number)
	if self.lastEquippedChoice == self.weaponSlots[slotIndex].CurrentItem then
		self:CharacterClearLastTool()
		self.lastEquippedChoice = nil
	end
end

--[[

	WEAPON SELECTION

]]

function LoadoutUI:UpdateOwnedWeapons()
	local ownedItems = Remotes.GetOwnedItems:InvokeServer() :: { string }
	if not ownedItems then
		warn("No owned items provided")
		return
	end

	self.ownedItems = ownedItems
end

function LoadoutUI:UpdateWeaponSelection()
	local ScrollingFrame = self.weaponSelection:FindFirstChild("ScrollingFrame")
	local Reference = ScrollingFrame:FindFirstChild("Reference")
	self.lastOwnedItems = table.clone(self.ownedItems)
	self:UpdateOwnedWeapons()

	local tablesMatch = false
	for i, v in ipairs(self.lastOwnedItems) do
		if v ~= self.ownedItems[i] then
			tablesMatch = false
			break
		end
		tablesMatch = true
	end

	-- Only update all our frames if the owned items have changed, otherwise we can just return
	if not tablesMatch then
		print("Owned items changed, updating weapon selection")

		for _, child in ipairs(self.weaponChoices) do
			child.Button:Destroy()
		end

		table.clear(self.weaponChoices)

		-- TODO: Integrate filtering
		for _, ownedItem in ipairs(self.ownedItems) do
			local newButton = Reference:Clone() :: ImageButton
			local WeaponImage = newButton:FindFirstChild("WeaponImage")
			local WeightIndicator = newButton:FindFirstChild("WeightIndicator")

			-- Get item info
			local itemInfo = RemoteInfo:InvokeServer(ownedItem)
			if not itemInfo then
				warn(`No item info for {ownedItem}`)
				continue
			end

			WeightIndicator.Image = WEIGHT_TO_IMAGE[itemInfo.Weight] or WEIGHT_TO_IMAGE["Light"]

			newButton.Title.Text = itemInfo.Name
			WeaponImage.Image = itemInfo.PreviewImage

			newButton.Visible = true
			newButton.Parent = ScrollingFrame

			local weaponChoice = {
				Name = itemInfo.Name,
				Weight = itemInfo.Weight,
				PreviewImage = itemInfo.PreviewImage,
				Button = newButton,
			}

			table.insert(self.weaponChoices, weaponChoice)

			self:HookBaseButtonSounds(newButton)

			newButton.MouseButton1Down:Connect(function()
				print(`Equipping {ownedItem}`)

				local success, message = self:EquipWeaponToSlot(weaponChoice, self.lastSelectedSlot.SlotIndex)
				if success then
					self:PlaySound("Equip")
					self.weaponSelection.Visible = false
					self:HideWeaponSelection()
					self:HideEstimatedFill()
				else
					self:PlaySound("Error")
					if message == "Weight" then
						-- moves it
						self:ShowEstimatedFill(weaponChoice)
						self:FlashWeightBar()
					end
				end
			end)

			newButton.MouseEnter:Connect(function()
				self:ShowEstimatedFill(weaponChoice)
			end)

			newButton.MouseLeave:Connect(function()
				self:HideEstimatedFill()
			end)
		end
	end

	-- Filter phase
	for _, weaponChoice: WeaponChoice in ipairs(self.weaponChoices) do
		local shouldShow = true

		local alreadyEquipped = self:GetSlotWithWeaponName(weaponChoice.Name)
		local Image = weaponChoice.Button:FindFirstChild("WeaponImage") :: ImageLabel
		if alreadyEquipped then
			-- its fine, but we should warn them if they try to equip it
			Image.ImageTransparency = 0.5
		else
			-- weapons can be unequipped while its open, best to reset it
			Image.ImageTransparency = 0
		end

		-- Filter by search name
		if self.searchName ~= "" then
			if not string.find(string.lower(weaponChoice.Name), string.lower(self.searchName)) then
				shouldShow = false
			end
		end

		if not table.find(self.validWeights, weaponChoice.Weight) then
			shouldShow = false
		end

		weaponChoice.Button.Visible = shouldShow
	end
end

function LoadoutUI:ShowWeaponSelection()
	if self.weaponSelectionVisible then
		return
	end

	-- usually you want to pick a DIFFERENT weapon
	self.searchBox.Text = ""
	self.searchName = ""

	self:PlaySound("Expand")

	-- can be slow
	task.defer(function()
		self:UpdateWeaponSelection()
	end)

	self.weaponSelectionVisible = true
	self.weaponSelection.Visible = true

	local UIScale = self.weaponSelection:FindFirstChild("UIScale")
	if UIScale then
		UIScale.Scale = 0
		TweenService
			:Create(UIScale, TweenInfo.new(0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { Scale = 1 })
			:Play()
	end
end

function LoadoutUI:HideWeaponSelection()
	if not self.weaponSelectionVisible then
		return
	end

	self.weaponSelectionVisible = false

	local UIScale = self.weaponSelection:FindFirstChild("UIScale")
	if UIScale then
		local tween = TweenService:Create(
			UIScale,
			TweenInfo.new(0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
			{ Scale = 0 }
		)
		tween:Play()

		-- make it not visible after completion
		-- assuming they didnt open it again
		tween.Completed:Connect(function(_: Enum.PlaybackState)
			if self.weaponSelectionVisible then
				return
			end
			self.weaponSelection.Visible = false
		end)
	end
end

function LoadoutUI:SetWeightSelected(button: ImageButton, isSelected: boolean)
	button.ImageColor3 = if isSelected then Color3.fromRGB(0, 0, 0) else Color3.fromRGB(255, 255, 255)
	button.BackgroundColor3 = if isSelected then Color3.fromRGB(255, 255, 255) else Color3.fromRGB(0, 0, 0)
	button.BackgroundTransparency = if isSelected then 0 else 0.5

	if isSelected then
		local index = table.find(self.validWeights, button.Name)
		if not index then
			table.insert(self.validWeights, button.Name)
		end
	else
		local index = table.find(self.validWeights, button.Name)
		if index then
			table.remove(self.validWeights, index)
		end
	end
end

--[[

	WEIGHT SYSTEM

]]

function LoadoutUI:GetTotalWeight(): number
	local totalWeight = 0

	for _, slot in ipairs(self.weaponSlots) do
		if slot.Weight == "Light" then
			totalWeight += self.loadoutConfig.lightWeaponWeight
		elseif slot.Weight == "Moderate" then
			totalWeight += self.loadoutConfig.mediumWeaponWeight
		elseif slot.Weight == "Heavy" then
			totalWeight += self.loadoutConfig.heavyWeaponWeight
		end
	end

	return totalWeight
end

--- Intended for being overweight/not being able to be equipped
function LoadoutUI:FlashWeightBar()
	if self.flashing then
		return
	end

	self.flashing = true

	local barFill = self.weightBar:FindFirstChild("Fill") :: Frame
	local weightIcon = self.weightBar:FindFirstChild("WeightIcon") :: ImageLabel
	local originalColor = barFill.BackgroundColor3

	barFill.BackgroundColor3 = Color3.fromRGB(100, 0, 0)
	weightIcon.ImageColor3 = Color3.fromRGB(100, 0, 0)

	TweenService:Create(
		barFill,
		TweenInfo.new(0.4, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		{ BackgroundColor3 = originalColor }
	):Play()

	local weightTween = TweenService:Create(
		weightIcon,
		TweenInfo.new(0.4, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		{ ImageColor3 = originalColor }
	)
	weightTween:Play()
	weightTween.Completed:Connect(function()
		self.flashing = false
	end)
end

function LoadoutUI:GetWeightForSlot(slotIndex: number): number
	local slot = self.weaponSlots[slotIndex] :: WeaponSlot
	if not slot then
		warn(`No slot found for index {slotIndex}`, self.weaponSlots)
		return 0
	end

	if slot.Weight == "Light" then
		return self.loadoutConfig.lightWeaponWeight
	elseif slot.Weight == "Moderate" then
		return self.loadoutConfig.mediumWeaponWeight
	elseif slot.Weight == "Heavy" then
		return self.loadoutConfig.heavyWeaponWeight
	end

	return 0
end

function LoadoutUI:CanEquipWeaponInSlot(weaponChoice: WeaponChoice, slotIndex: number): boolean
	local currentWeight = self:GetTotalWeight()
	local slotWeight = self:GetWeightForSlot(slotIndex)

	-- check to see if this is already in another slot
	-- that way we can remove its weight from the total if it is
	local existingSlot = self:GetSlotWithWeaponName(weaponChoice.Name)
	if existingSlot and existingSlot.SlotIndex ~= slotIndex then
		currentWeight -= self:GetWeightForSlot(existingSlot.SlotIndex)
	end

	local newWeaponWeight = 0
	if weaponChoice.Weight == "Light" then
		newWeaponWeight = self.loadoutConfig.lightWeaponWeight
	elseif weaponChoice.Weight == "Moderate" then
		newWeaponWeight = self.loadoutConfig.mediumWeaponWeight
	elseif weaponChoice.Weight == "Heavy" then
		newWeaponWeight = self.loadoutConfig.heavyWeaponWeight
	end

	local newTotalWeight = currentWeight - slotWeight + newWeaponWeight

	return newTotalWeight <= self.loadoutConfig.maxWeight
end

function LoadoutUI:ShowEstimatedFill(weaponChoice: WeaponChoice)
	local addedWeight = weaponChoice.Weight == "Light" and self.loadoutConfig.lightWeaponWeight
		or weaponChoice.Weight == "Moderate" and self.loadoutConfig.mediumWeaponWeight
		or weaponChoice.Weight == "Heavy" and self.loadoutConfig.heavyWeaponWeight
		or 0

	local fill = self.weightBar:FindFirstChild("Fill") :: Frame
	local estimatedFill = self.weightBar:FindFirstChild("EstimatedFill") :: Frame
	estimatedFill.BackgroundColor3 = fill.BackgroundColor3
	estimatedFill.Size = fill.Size
	estimatedFill.Visible = true
	local totalWeight = self:GetTotalWeight()

	local existingSlot = self:GetSlotWithWeaponName(weaponChoice.Name)
	if existingSlot then
		totalWeight -= addedWeight
	end

	-- if there's a weapon you're replacing in the slot, we need to subtract its weight from the total
	local replacedSlot = self.lastSelectedSlot
	if replacedSlot and replacedSlot.CurrentItem ~= "None" then
		totalWeight -= self:GetWeightForSlot(replacedSlot.SlotIndex)
	end

	local fillPercentage = (totalWeight + addedWeight) / self.loadoutConfig.maxWeight
	estimatedFill:TweenSize(
		UDim2.new(fillPercentage, 0, 1, 0),
		Enum.EasingDirection.Out,
		Enum.EasingStyle.Quint,
		0.5,
		true
	)
end

function LoadoutUI:HideEstimatedFill()
	local estimatedFill = self.weightBar:FindFirstChild("EstimatedFill") :: Frame
	estimatedFill.Visible = false
end

function LoadoutUI:UpdateWeightBar()
	local barFill = self.weightBar:FindFirstChild("Fill") :: Frame
	local weightIcon = self.weightBar:FindFirstChild("WeightIcon") :: ImageLabel
	local totalWeight = self:GetTotalWeight()
	print(totalWeight, "/", self.loadoutConfig.maxWeight)

	local fillPercentage = totalWeight / self.loadoutConfig.maxWeight
	barFill:TweenSize(UDim2.new(fillPercentage, 0, 1, 0), Enum.EasingDirection.Out, Enum.EasingStyle.Quint, 0.5, true)

	local bgColor = Color3.new(1, 1, 1)
	if fillPercentage > 0.8 then
		bgColor = Color3.fromRGB(255, 0, 0)
	elseif fillPercentage > 0.6 then
		bgColor = Color3.fromRGB(255, 255, 0)
	end

	if barFill.BackgroundColor3 ~= bgColor then
		TweenService:Create(
			barFill,
			TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
			{ BackgroundColor3 = bgColor }
		):Play()

		TweenService:Create(
			weightIcon,
			TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
			{ ImageColor3 = bgColor }
		):Play()
	end
end

--[[

	SLOT SYSTEM

]]

function LoadoutUI:SetSlotSelected(Slot: WeaponSlot, isSelected: boolean)
	if not Slot then
		warn("Invalid slot passed to slot selection:", typeof(Slot))
		return
	end

	local Button = Slot.Button
	local Line = Button.Line :: Frame
	local Stroke = Button.UIStroke :: UIStroke
	Stroke.Transparency = if isSelected then 0 else 1

	if isSelected then
		Line.Size = UDim2.new(0, 0, 0.02, 0)
		Line:TweenSize(UDim2.new(0.12, 0, 0.02, 0), Enum.EasingDirection.Out, Enum.EasingStyle.Quint, 0.5)
	else
		Line.Size = UDim2.new(0, 0, 0.02, 0)
	end

	Line.Visible = isSelected
end

function LoadoutUI:SlotSelected(slotIndex: number)
	local selectedSlot = self.weaponSlots[slotIndex] :: WeaponSlot
	local lastSlot = self.lastSelectedSlot :: WeaponSlot

	if selectedSlot == lastSlot then
		self:SetSlotSelected(lastSlot, false)
		self:HideWeaponSelection()
		self.lastSelectedSlot = nil
		return
	end

	if lastSlot then
		self:SetSlotSelected(lastSlot, false)
	end

	self:SetSlotSelected(selectedSlot, true)
	self.lastSelectedSlot = selectedSlot
	print(`Slot {slotIndex} selected`)
	self:ShowWeaponSelection()
end

function LoadoutUI:GetSlotWithWeaponName(weaponName: string): WeaponSlot?
	for _, slot in pairs(self.weaponSlots) do
		if slot.CurrentItem == weaponName then
			return slot
		end
	end
	return nil
end

function LoadoutUI:ClearWeaponInSlot(slotIndex: number)
	local slot = self.weaponSlots[slotIndex] :: WeaponSlot
	if not slot then
		warn(`No slot found for index {slotIndex}`, self.weaponSlots)
		return
	end

	local Button = slot.Button
	local WeaponImage = Button:FindFirstChild("WeaponImage") :: ImageLabel
	local Title = Button:FindFirstChild("Title") :: TextLabel
	local EmptyText = Button:FindFirstChild("EmptyText") :: TextLabel

	WeaponImage.Image = "rbxassetid://6302778252"
	WeaponImage.ImageTransparency = 0.91
	Title.BackgroundColor3 = Color3.fromRGB(99, 99, 99)
	Title.Text = "WEAPON SLOT"
	EmptyText.Text = "EMPTY"
	slot.CurrentItem = "None"
	slot.Weight = nil
end

--[[

	SHOW/HIDE MAIN UI

]]

function LoadoutUI:Start()
	self.started = true
end

function LoadoutUI:Show()
	if self.isShowing then
		return
	end
	self.alive = true
	self.isShowing = true

	self.mainFrame.Position = UDim2.new(0.5, 0, 2, 0)

	lockCamera()

	local screenTransition = fadeScreen()
	screenTransition.Completed:Wait()

	Camera.CFrame = self.baseCameraCFrame

	self:SetupRenderConnect()
	showScreen()

	if self.mainFrame then
		self.mainFrame.Visible = true
	end

	self.mainFrame:TweenPosition(UDim2.new(0.5, 0, 0.5, 0), Enum.EasingDirection.Out, Enum.EasingStyle.Quad, 0.5, true)
end

function LoadoutUI:Hide(exitting: boolean?, destroyAfterFade: boolean?)
	self.alive = false

	if not self.isShowing then
		return
	end

	self.isShowing = false

	if self.connection then
		self.connection:Disconnect()
		self.connection = nil
	end

	self.mainFrame:TweenPosition(
		UDim2.new(0.5, 0, 2, 0),
		Enum.EasingDirection.Out,
		Enum.EasingStyle.Quint,
		1,
		true,
		function()
			if exitting and (destroyAfterFade == nil or destroyAfterFade) then
				task.delay(3, function()
					self:Destroy()
				end)
			end
		end
	)

	if exitting then
		fadeScreen().Completed:Wait()
		returnCamera()
		Player:SetAttribute("InShop", false)
		showScreen()
	else
		fadeScreen().Completed:Wait()
		task.delay(1, function()
			showScreen()
		end)
	end
end

function LoadoutUI:RequestExit()
	if self.onExitRequested then
		self.onExitRequested()
	end
end

function LoadoutUI:Destroy()
	self.alive = false
	if self.connection then
		self.connection:Disconnect()
		self.connection = nil
	end

	if self.mainFrame and self.mainFrame.Parent then
		self.mainFrame:Destroy()
	end
	if self.loadoutCharacter and self.loadoutCharacter.Parent then
		self.loadoutCharacter:Destroy()
	end
end

return LoadoutUI
