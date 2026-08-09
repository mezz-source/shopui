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
local GetPlayerLoadouts = Remotes:WaitForChild("GetPlayerLoadouts")
local ValidateLoadout = Remotes:WaitForChild("ValidateLoadout")
local RemoveLoadout = Remotes:WaitForChild("RemoveLoadout")
local SetActiveLoadout = Remotes:FindFirstChild("SetActiveLoadout")
local LoadoutConfigs = script.Parent.Parent:WaitForChild("LoadoutConfigs")
local WeaponPreviews = ReplicatedStorage:WaitForChild("WeaponPreview")
local RequestLoadout = Remotes:WaitForChild("RequestLoadout")

local Datastore = ReplicatedStorage:WaitForChild("Datastore")
local GetPlayerInventory = Datastore:WaitForChild("getPlayerInventory")

local ShopTypes = require(ReplicatedStorage.ShopClient.ShopTypes)
local AnimationHandler = require(script.Parent.Parent.AnimationHandler)
local InvokeLogger = require(script.Parent.Parent.InvokeLogger)

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

	LOADOUT HELPER

]]

--- One exit of the loadout state, requests the new loadout from the server and applies to the player
--- This should be done infrequently as the server aggressively throttles this
--- ... which is why we do it only when they exit the loadout screen
local function finalRequestLoadout(loadoutName: string)
	task.spawn(function()
		local result = RequestLoadout:InvokeServer(loadoutName)
		local success = result["Success"]
		local reason = result["Reason"]
		if not success then
			warn("Equip loadout failure:", reason)
		end
	end)
end

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

	LOADOUT BUTTONS

]]

local function selectLoadoutButton(button)
	if not button then
		return
	end
	button.BackgroundTransparency = 0
	button.BackgroundColor3 = Color3.new(1, 1, 1)
	button.WeaponName.TextColor3 = Color3.new(0, 0, 0)
	button.RemoveButton.ImageColor3 = Color3.new(0, 0, 0)
end

local function unselectLoadoutButton(button)
	if not button then
		return
	end
	-- print("unsel", button.Name)
	button.BackgroundTransparency = 0.5
	button.BackgroundColor3 = Color3.new(0, 0, 0)
	button.WeaponName.TextColor3 = Color3.new(1, 1, 1)
	button.RemoveButton.ImageColor3 = Color3.new(1, 1, 1)
end

--[[

	CHARACTER EQUIP/ANIMATION HANDLER

]]

local function getAnimsFromGunModel(model: Model): { ["Idle"]: string, ["Equip"]: string }
	local Setting = model:FindFirstChild("Setting")
	if not Setting then
		warn("Gun", model.Name, "is missing settings module")
		return { Idle = "0", Equip = "0" }
	end

	local module = require(Setting)
	return {
		Idle = tostring(module.IdleAnimationID or 0),
		Equip = tostring(module.EquippedAnimationID or 0),
	}
end

local function getAnimsFromMeleeModel(model: Model): { ["Idle"]: string, ["Equip"]: string }
	local Animations = model:FindFirstChild("Animations") :: Folder
	if not Animations then
		warn("Melee weapon", model.Name, "is missing animations")
		return { Idle = "0", Equip = "0" }
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

local function getSoundsFromGunModel(model: Model): { ["Equip"]: Sound? }
	local Setting = model:FindFirstChild("Setting")
	if not Setting then
		warn("Gun", model.Name, "is missing settings module")
		return { Equip = nil }
	end

	local PrimaryHandle = model:FindFirstChild("Handle")
		or model:FindFirstChild("NotHandle")
		or model:FindFirstChild("4 - Base")
	if not PrimaryHandle then
		warn("Gun", model.Name, "is missing a primary handle")
		return { Equip = nil }
	end

	local EquippedSound = PrimaryHandle:FindFirstChild("EquippedSound")
	if not EquippedSound then
		warn("Gun", model.Name, "is missing an EquippedSound")
		return { Equip = nil }
	end

	return {
		Equip = EquippedSound :: Sound,
	}
end

local function getSoundsFromMeleeModel(model: Model): { ["Equip"]: Sound? }
	local PrimaryHandle = model:FindFirstChild("Handle")
		or model:FindFirstChild("4 - Base")
		or model:FindFirstChild("NotHandle")
	if not PrimaryHandle then
		warn("Melee weapon", model.Name, "is missing a primary handle")
		return { Equip = nil }
	end

	local EquippedSound = PrimaryHandle:FindFirstChild("EquipSound")
	if not EquippedSound then
		warn("Melee weapon", model.Name, "is missing an EquipSound")
		return { Equip = nil }
	end

	return {
		Equip = EquippedSound :: Sound,
	}
end

function LoadoutUI:CharacterWeldWeapon(weaponModel: Model)
	local Base4 = weaponModel:FindFirstChild("4 - Base")
	local NotHandle = weaponModel:FindFirstChild("NotHandle")

	if Base4 then
		Base4.Anchored = false
		-- print("Base4")
		self.base4Weld.Part1 = Base4
		self.base4Weld.Part0 = self.characterRightArm
		self.base4Weld.C0 = CFrame.new(0, 0, 0)
		self.base4Weld.C1 = CFrame.new(0, 0, 0)
	end

	if NotHandle then
		NotHandle.Anchored = false
		-- print("NotHandle")
		self.notHandleWeld.Part1 = NotHandle
		self.notHandleWeld.Part0 = self.characterRightArm
		self.notHandleWeld.C0 = CFrame.new(0, 0, 0)
		self.notHandleWeld.C1 = CFrame.new(0, 0, 0)
	end

	-- If neither special parts exist, try to weld the regular Handle
	if not Base4 and not NotHandle then
		-- print("Neither Base4 nor NotHandle found, trying to weld Handle")
		local Handle = weaponModel:FindFirstChild("Handle")

		if Handle then
			Handle.Anchored = false
			-- print("Handle")
			-- Use an existing handleWeld if present, otherwise fall back to base4Weld
			local weld = self.rightGrip
			weld.Part1 = Handle
			weld.Part0 = self.characterRightArm

			local GripCFrame = weaponModel:GetAttribute("GripCFrame") or CFrame.new(0, 0, 0)
			weld.C1 = GripCFrame
		end
	end
end

function LoadoutUI:CharacterPlayToolSounds(weaponModel)
	local isGun = weaponModel:FindFirstChild("Setting") ~= nil

	local success, result = pcall(function()
		if isGun then
			return getSoundsFromGunModel(weaponModel)
		else
			return getSoundsFromMeleeModel(weaponModel)
		end
	end)

	if not success then
		warn("Failed to get sounds for weapon model", weaponModel.Name, result)
		return
	end

	-- Check to make sure results are numbers
	if typeof(result) ~= "table" then
		warn(result)
		warn("Failed to load sounds for weapon model", weaponModel.Name, "invalid sound ids")
		return
	end

	local sound = result["Equip"]
	if sound then
		sound:Play()
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
	equip:Play(0)

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
	self:CharacterPlayToolSounds(clone)
end

function LoadoutUI:ChangedEffects()
	if not self.characterModel or self.isShowing then
		return
	end

	if self.lastHighlightTween then
		self.lastHighlightTween:Pause()
	end

	local Highlight = self.characterModel:FindFirstChild("Highlight") :: Highlight
	local DustPart = self.characterModel:FindFirstChild("Dust")
	local FlyUp = DustPart:FindFirstChild("FlyUp") :: ParticleEmitter
	FlyUp:Emit(30)

	Highlight.FillTransparency = 0

	local tween = TweenService:Create(
		Highlight,
		TweenInfo.new(1, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		{ FillTransparency = 1 }
	)

	self.lastHighlightTween = tween

	tween:Play()
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

	LOADOUT CREATION, LOADING, DELETION

]]

function LoadoutUI:SetLoadoutStatusText(text: string, isError: boolean)
	local statusText = self.loadoutStatusText :: TextLabel
	statusText.Text = text
	statusText.TextColor3 = isError and Color3.fromRGB(255, 0, 0) or Color3.fromRGB(255, 255, 255)
	statusText.TextTransparency = 0

	if self.fadeThread then
		coroutine.close(self.fadeThread)
	end

	if self.fadeTween then
		self.fadeTween:Cancel()
	end

	self.fadeThread = coroutine.create(function()
		task.wait(3)
		self.fadeTween = TweenService:Create(statusText, TweenInfo.new(1), { TextTransparency = 1 })
		self.fadeTween:Play()
	end)

	coroutine.resume(self.fadeThread)
end

function LoadoutUI:LoadoutMatches(loadoutA: ShopTypes.Loadout, loadoutB: ShopTypes.Loadout): boolean
	if #loadoutA ~= #loadoutB then
		return false
	end

	for i = 1, #loadoutA do
		if loadoutA[i] ~= loadoutB[i] then
			return false
		end
	end

	return true
end

function LoadoutUI:GetLoadoutFromSlots(slots: { WeaponSlot }): ShopTypes.Loadout
	local loadout: ShopTypes.Loadout = {}
	for i, slot in ipairs(slots) do
		loadout[i] = slot.CurrentItem
	end
	return loadout
end

function LoadoutUI:CreateLoadoutFromSlots(name: string, slots: { WeaponSlot })
	local response = InvokeLogger.invokeServer(ValidateLoadout, name, self:GetLoadoutFromSlots(slots))
	local success, reason = response["Success"], response["Reason"]
	if success then
		if typeof(response["Loadouts"]) == "table" then
			self.loadouts = response["Loadouts"]
		end
		self.loadoutAddButton.ImageColor3 = Color3.new(1, 1, 1)
		self:SetLoadoutStatusText(`{name} saved successfully`, false)
		self.activeLoadoutName = name
		self.currentLoadoutName = name
		return true
	else
		warn(`Failed to create loadout {name}: {reason}`)
		self:SetLoadoutStatusText(reason, true)
		return false
	end
end

function LoadoutUI:LoadLoadoutIntoSlots(loadout: ShopTypes.Loadout)
	self.isApplyingLoadout = true

	for i, slot in ipairs(self.weaponSlots) do
		local weaponName = loadout[i]
		if weaponName then
			local isEmpty = weaponName == "None"
			if isEmpty then
				self:UnequipWeaponFromSlot(i, false)
				continue
			end
			local itemInfo = self:GetWeaponInfoCached(weaponName)
			if itemInfo then
				local weaponChoice = {
					Name = itemInfo.Name,
					Weight = itemInfo.Weight,
					PreviewImage = itemInfo.PreviewImage,
					Button = nil,
					IsTorsoDominant = itemInfo["IsTorsoDominant"] or false,
				}
				local isFirstSlot = i == 1
				self:EquipWeaponToSlot(weaponChoice, i, isFirstSlot)
			else
				warn(`Failed to load weapon info for {weaponName}, clearing slot {i}`)
				self:UnequipWeaponFromSlot(i, false)
			end
		else
			self:UnequipWeaponFromSlot(i, true)
		end
	end

	self.isApplyingLoadout = false
	self:SyncLoadoutSelectionState()
end

function LoadoutUI:DeleteLoadout(name: string)
	if self.isDeletingLoadout then
		return false
	end

	self.isDeletingLoadout = true

	local result = InvokeLogger.invokeServer(RemoveLoadout, name)
	local success = result["Success"]
	local message = result["Reason"]
	if not success then
		self:SetLoadoutStatusText(message, true)
		warn(message)
	else
		if typeof(result["Loadouts"]) == "table" then
			self.loadouts = result["Loadouts"]
		end
	end

	self.isDeletingLoadout = false

	return success
end

function LoadoutUI:SetActiveLoadout(loadoutName: string)
	-- This is slow so lets save this after we're done
	task.defer(function()
		if SetActiveLoadout and SetActiveLoadout:IsA("RemoteFunction") then
			local callSuccess, response = pcall(function()
				return InvokeLogger.invokeServer(SetActiveLoadout, loadoutName)
			end)

			if not callSuccess then
				warn(`Failed to set active loadout '{loadoutName}': {response}`)
			elseif typeof(response) == "table" and response["Success"] == false then
				warn(`Failed to set active loadout '{loadoutName}': {response["Reason"] or "Unknown reason"}`)
			end
		else
			warn("ShopRemotes.SetActiveLoadout is missing")
		end
	end)
end

function LoadoutUI:EquipLoadout(loadoutName: string, loadout: ShopTypes.Loadout, noSound: boolean?)
	if self.isApplyingLoadout then
		return
	end

	local isNew = loadoutName ~= self.currentLoadoutName

	if isNew then
		self:CharacterClearLastTool()
		self.activeLoadoutName = loadoutName
		self.loadoutNameEntry.Text = loadoutName
		self:SetActiveLoadout(loadoutName)
		self.currentLoadoutName = loadoutName
		self.loadoutAddButton.ImageColor3 = Color3.new(1, 1, 1)
		if not noSound then
			self:PlaySound("Equip")
		end
	end

	self:LoadLoadoutIntoSlots(loadout)
	self:UpdateWeightBar()
end

function LoadoutUI:SyncLoadoutSelectionState()
	if self.isApplyingLoadout then
		return
	end

	local selectedLoadout = self.loadouts[self.currentLoadoutName]
	if typeof(selectedLoadout) ~= "table" then
		-- No matching saved loadout, mark as custom
		unselectLoadoutButton(self.lastSelectedLoadoutButton)
		self.lastSelectedLoadoutButton = nil
		if self.currentLoadoutName ~= "Custom" then
			-- print(self.currentLoadoutName)
		end
		self.currentLoadoutName = "Custom"
		self.loadoutAddButton.ImageColor3 = Color3.new(1, 1, 0)
		return
	end

	local currentSlots = self:GetLoadoutFromSlots(self.weaponSlots)
	local loadoutMatches = self:LoadoutMatches(selectedLoadout, currentSlots)
	if loadoutMatches then
		return
	end

	unselectLoadoutButton(self.lastSelectedLoadoutButton)

	-- print(self.currentLoadoutName)
	self.lastSelectedLoadoutButton = nil
	self.currentLoadoutName = "Custom"
	self.loadoutAddButton.ImageColor3 = Color3.new(1, 1, 0)
end

function LoadoutUI:BounceAddLoadoutButton()
	if not self.loadoutAddButton then
		return
	end

	local addButton = self.loadoutAddButton :: TextButton
	local uiScale = addButton:FindFirstChild("UIScale")
	if not uiScale then
		uiScale = Instance.new("UIScale")
		uiScale.Parent = addButton
	end

	local shrinkTween = TweenService:Create(
		uiScale,
		TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Scale = 0.9 }
	)
	local growTween = TweenService:Create(
		uiScale,
		TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = 1 }
	)

	shrinkTween:Play()
	task.delay(0.08, function()
		growTween:Play()
	end)
end

function LoadoutUI:CreateLoadoutButton(loadoutName: string, loadout: ShopTypes.Loadout)
	local reference = self.loadoutScroll:FindFirstChild("Reference") :: Frame
	local buttonClone = reference:Clone() :: TextButton
	local removeButton = buttonClone:WaitForChild("RemoveButton") :: ImageButton
	local weaponName = buttonClone.WeaponName :: TextLabel
	buttonClone.Name = loadoutName
	buttonClone.Visible = true
	buttonClone.Parent = self.loadoutScroll
	weaponName.Text = loadoutName
	self.loadouts[loadoutName] = loadout

	buttonClone.MouseButton1Down:Connect(function()
		if self.lastSelectedLoadoutButton and self.lastSelectedLoadoutButton ~= buttonClone then
			-- print("unselect")
			unselectLoadoutButton(self.lastSelectedLoadoutButton)
		end

		self.lastSelectedLoadoutButton = buttonClone

		selectLoadoutButton(buttonClone)
		local selectedLoadout = self.loadouts[loadoutName] or loadout
		self:EquipLoadout(loadoutName, selectedLoadout)
	end)

	removeButton.MouseButton1Down:Connect(function()
		if not self:DeleteLoadout(loadoutName) then
			return
		end

		self.loadouts[loadoutName] = nil

		if self.lastSelectedLoadoutButton == buttonClone then
			self.lastSelectedLoadoutButton = nil
		end

		self:PlaySound("Unequip")
		buttonClone:Destroy()
	end)

	self:HookBaseButtonSounds(buttonClone)
	self:HookBaseButtonSounds(removeButton)
	return buttonClone
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
	self.infoLibrary = nil
	self.loadoutCharacter = LoadoutCharacterRef:Clone()
	self.loadoutCharacter.Parent = workspace
	self.loadoutConfig = getLoadoutConfig()
	self.sounds = {}
	self.weaponSlots = {}
	self.ownedItems = {}
	self.weaponChoices = {}

	-- TODO: Implement "Custom" loadout switch
	-- The user can load a loadout, change something, then reslect it
	-- Otherwise we accidentally lock them out
	self.loadouts = {}
	self.lastLoadoutList = {}
	self.currentLoadoutName = "Default"
	self.activeLoadoutName = "Default"
	self.setLoadoutName = ""
	self.addLoadoutLocked = false
	self.isApplyingLoadout = false
	self.isDeletingLoadout = false

	self.validWeights = { "Light", "Moderate", "Heavy" }
	self.searchName = ""

	self.lastSelectedLoadoutButton = nil
	self.lastSelectedSlot = nil
	self.confirmed = false

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
				if self.currentLoadoutName == "Custom" and not self.confirmed then
					self:PlaySound("Error")
					self:SetLoadoutStatusText(
						"Warning: You have not saved this loadout!\nPress exit to leave anyways",
						true
					)
					self.confirmed = true

					task.delay(5, function()
						self.confirmed = false
					end)

					return
				end

				self:RequestExit()
			end)
		end
	end

	self:Init()

	return self
end

function LoadoutUI:RefreshLoadoutSelection()
	local rawResult = InvokeLogger.invokeServer(GetPlayerLoadouts)
	local inventorySetting = InvokeLogger.invokeServer(GetPlayerInventory)
	local activeLoadout = inventorySetting["ActiveLoadout"] or "Default"
	local getSavedLoadouts = rawResult

	--- Remove existing loadout buttons
	for _, button in ipairs(self.loadoutScroll:GetChildren()) do
		if button:IsA("TextButton") and button.Name ~= "Reference" then
			button:Destroy()
		end
	end

	if typeof(rawResult) == "table" and rawResult["Success"] ~= nil then
		if not rawResult["Success"] then
			local reason = rawResult["Reason"] or "Failed to load saved loadouts"
			self:SetLoadoutStatusText(reason, true)
			warn(reason)
			getSavedLoadouts = {}
		else
			getSavedLoadouts = rawResult["Loadouts"] or {}
		end
	end

	self.loadouts = getSavedLoadouts

	for name, loadout in pairs(getSavedLoadouts) do
		local button = self:CreateLoadoutButton(name, loadout)
		if name == activeLoadout then
			self:EquipLoadout(name, loadout, true)
			self.lastSelectedLoadoutButton = button
			selectLoadoutButton(button)
			self.loadoutNameEntry.Text = name
		end
	end
end

function LoadoutUI:Init()
	self:LoadSounds()
	self:InitCharacter()
	self:InitButtons()

	self:InitFrameInstances()
	self:InitConfigSlots()
end

function LoadoutUI:GetWeaponInfoCached(weaponName: string, forceRefresh: boolean?): ShopTypes.WeaponInfo?
	if self.infoLibrary then
		return self.infoLibrary.getWeaponInfo(weaponName)
	end
	return nil
end

function LoadoutUI:GetOwnedItemsCached(forceRefresh: boolean?): { string }
	if self.infoLibrary then
		if forceRefresh then
			return self.infoLibrary.refreshOwnedItems()
		end
		return self.infoLibrary.getOwnedItems()
	end
	return table.clone(self.ownedItems)
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

	for _, child in ipairs(WeightFilters:GetChildren()) do
		if child:IsA("ImageButton") and child:HasTag("Weight") then
			child.MouseButton1Down:Connect(function()
				local isSelected = child.BackgroundTransparency == 0
				self:SetWeightSelected(child, not isSelected)
				self:UpdateWeaponSelection()
			end)
		end
	end

	local WeaponSlots = UIFrame:WaitForChild("WeaponSlots")
	local LoadoutArea = UIFrame:WaitForChild("LoadoutArea")
	local LoadoutStatusText = LoadoutArea:WaitForChild("LoadoutStatusText")
	local LoadoutEntry = LoadoutArea:WaitForChild("LoadoutEntry")
	local AddLoadoutButton = LoadoutEntry:WaitForChild("Add")
	local LoadoutNameEntry = LoadoutEntry.EntryArea:WaitForChild("TextBox")
	local LoadoutScroll = LoadoutArea:WaitForChild("LoadoutScroll")
	LoadoutNameEntry:GetPropertyChangedSignal("Text"):Connect(function()
		self.setLoadoutName = LoadoutNameEntry.Text
	end)

	self.loadoutScroll = LoadoutScroll
	self.loadoutStatusText = LoadoutStatusText
	self.loadoutAddButton = AddLoadoutButton
	self.loadoutNameEntry = LoadoutNameEntry
	self.loadoutScroll = LoadoutScroll

	self.searchBox = SearchTextBox
	self.weaponSlotsUI = WeaponSlots
	self.weaponSelection = WeaponSelection
	self.weightBar = WeightBar

	AddLoadoutButton.MouseButton1Down:Connect(function()
		if self.addLoadoutLocked then
			return
		end

		if self.setLoadoutName == "" then
			self:SetLoadoutStatusText(`Loadout name cannot be empty`, true)
			warn("Cannot create loadout with empty name")
			return
		end

		self.addLoadoutLocked = true
		self:BounceAddLoadoutButton()

		local success = self:CreateLoadoutFromSlots(self.setLoadoutName, self.weaponSlots)
		if success then
			if self.loadouts[self.setLoadoutName] == nil then
				self.loadouts[self.setLoadoutName] = self:GetLoadoutFromSlots(self.weaponSlots)
			end
			-- check for existing button
			local button = LoadoutScroll:FindFirstChild(self.setLoadoutName)
			if not button then
				button = self:CreateLoadoutButton(self.setLoadoutName, self.loadouts[self.setLoadoutName])
			end

			-- Select this button
			if self.lastSelectedLoadoutButton then
				unselectLoadoutButton(self.lastSelectedLoadoutButton)
			end

			self.lastSelectedLoadoutButton = button

			selectLoadoutButton(button)

			-- Set active loadout
			self:SetActiveLoadout(self.setLoadoutName)
		end

		task.delay(0.5, function()
			self.addLoadoutLocked = false
		end)
	end)
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
			self:UnequipWeaponFromSlot(i, true)

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
			-- print(desc.Name)
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

	local idle = self.animationHandler:LoadAnimationById("112030243200049", "Idle", true) :: AnimationTrack
	local equip = self.animationHandler:LoadAnimationById("135602708513353", "EquipBounce", true) :: AnimationTrack
	local walkOn = self.animationHandler:LoadAnimationById("118529909671725", "WalkOn", true) :: AnimationTrack
	local empty = self.animationHandler:LoadAnimationById("129015535034160", "Empty", true) :: AnimationTrack
	local toolIdle = self.animationHandler:LoadAnimationById("180435571", "ToolIdle", true) :: AnimationTrack
	self.walkOnAnimation = walkOn
	self.emptyAnim = empty
	self.emptyIdleAnim = idle
	self.toolIdleAnim = toolIdle
	self.equipBounce = equip

	toolIdle.Looped = true
	idle.Looped = true
	idle:Play()

	equip.Priority = Enum.AnimationPriority.Action
	walkOn.Priority = Enum.AnimationPriority.Movement
	empty.Priority = Enum.AnimationPriority.Action2
	idle.Priority = Enum.AnimationPriority.Core
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

function LoadoutUI:UnequipWeaponFromSlot(slotIndex: number, unequipEffects: boolean?)
	local slot = self.weaponSlots[slotIndex] :: WeaponSlot
	if not slot then
		warn(`No slot found for index {slotIndex}`, self.weaponSlots)
		return
	end

	if unequipEffects then
		self:NewWeaponUnequipped(slotIndex)
	end

	self:ClearWeaponInSlot(slotIndex)
	self:UpdateWeightBar()
	self:SyncLoadoutSelectionState()
end

function LoadoutUI:EquipWeaponToSlot(
	weaponChoice: WeaponChoice,
	slotIndex: number,
	equipEffects: boolean?
): (boolean, string?)
	local slot = self.weaponSlots[slotIndex] :: WeaponSlot
	if not slot then
		warn(`No slot found for index {slotIndex}`, self.weaponSlots)
		return false, "Missing"
	end

	local canEquip = self:CanEquipWeaponInSlot(weaponChoice, slotIndex)
	if not canEquip then
		self:FlashWeightBar()
		return false, "WeightExceeded"
	end

	if self.lastSelectedSlot then
		self:SetSlotSelected(self.lastSelectedSlot, false)
	end

	self.lastSelectedSlot = nil

	local existingSlot = self:GetSlotWithWeaponName(weaponChoice.Name)
	if existingSlot then
		self:ClearWeaponInSlot(existingSlot.SlotIndex)
	end

	-- self.animationHandler:Stop("Empty")

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

	if equipEffects then
		self:NewWeaponEquipped(weaponChoice, slotIndex)
	end

	self:SyncLoadoutSelectionState()

	return true, "Success"
end

-- new equip effects
-- only use sounds for buttons
function LoadoutUI:NewWeaponEquipped(weaponChoice: WeaponChoice, slotIndex: number)
	-- effects
	local toolName = weaponChoice.Name
	self:CharacterEquipTool(toolName)
	self.lastEquippedChoice = weaponChoice.Name
	self.emptyAnim:Stop(0)
	self.equipBounce:Play(0)
	self:ChangedEffects()

	if toolName ~= "None" and weaponChoice.IsTorsoDominant then
		self.equipBounce:Stop(0) -- looks weird for default stand
		self.toolIdleAnim:Play(0)
		self.emptyIdleAnim:Stop(0)
		-- print("dominant cancel")
	elseif toolName ~= "None" and not weaponChoice.IsTorsoDominant then
		self.emptyIdleAnim:Play(0)
		self.toolIdleAnim:Stop(0)
		-- print("non-dominant cancel")
	end
end

-- new unequip effects
-- only use sounds for buttons
function LoadoutUI:NewWeaponUnequipped(slotIndex: number)
	self.equipBounce:Play(0)
	if self.lastEquippedChoice == self.weaponSlots[slotIndex].CurrentItem then
		self:CharacterClearLastTool()
		self.lastEquippedChoice = nil
		self.emptyIdleAnim:Play(0)
		self.toolIdleAnim:Stop(0)
		self.emptyAnim:Play(0)
		self:ChangedEffects()
	end
end

--[[

	WEAPON SELECTION

]]

function LoadoutUI:UpdateOwnedWeapons(forceRefresh: boolean?)
	self.ownedItems = self:GetOwnedItemsCached(forceRefresh)
end

function LoadoutUI:UpdateWeaponSelection(refreshOwnedItems: boolean?)
	local ScrollingFrame = self.weaponSelection:FindFirstChild("ScrollingFrame")
	local Reference = ScrollingFrame:FindFirstChild("Reference")
	self.lastOwnedItems = table.clone(self.ownedItems)
	self:UpdateOwnedWeapons(refreshOwnedItems)

	local tablesMatch = #self.lastOwnedItems == #self.ownedItems
	if tablesMatch then
		for i, v in ipairs(self.lastOwnedItems) do
			if v ~= self.ownedItems[i] then
				tablesMatch = false
				break
			end
		end
	end

	-- Only update all our frames if the owned items have changed, otherwise we can just return
	if not tablesMatch then
		-- print("Owned items changed, updating weapon selection")

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
			local itemInfo = self:GetWeaponInfoCached(ownedItem)
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
				IsTorsoDominant = itemInfo["IsTorsoDominant"] or false,
			}

			table.insert(self.weaponChoices, weaponChoice)

			self:HookBaseButtonSounds(newButton)

			newButton.MouseButton1Down:Connect(function()
				if not self.lastSelectedSlot then
					return
				end

				-- print(`Equipping {ownedItem}`)

				local success, message = self:EquipWeaponToSlot(weaponChoice, self.lastSelectedSlot.SlotIndex, true)
				if success then
					self:PlaySound("Equip")
					self.weaponSelection.Visible = false
					self:HideWeaponSelection()
					self:HideEstimatedFill()
				else
					self:PlaySound("Error")
					if message == "WeightExceeded" then
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
		self:UpdateWeaponSelection(true)
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
	else
		self.weaponSelection.Visible = false
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
		totalWeight -= self:GetWeightForSlot(existingSlot.SlotIndex)
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
	-- print(totalWeight, "/", self.loadoutConfig.maxWeight)

	local fillPercentage = totalWeight / self.loadoutConfig.maxWeight
	barFill:TweenSize(UDim2.new(fillPercentage, 0, 1, 0), Enum.EasingDirection.Out, Enum.EasingStyle.Quint, 0.5, true)

	local bgColor = Color3.new(1, 1, 1)
	if fillPercentage > 0.7 then
		bgColor = Color3.fromRGB(255, 0, 0)
	elseif fillPercentage > 0.5 then
		bgColor = Color3.fromRGB(255, 255, 0)
	end

	TweenService:Create(
		barFill,
		TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
		{ BackgroundColor3 = bgColor }
	):Play()

	TweenService
		:Create(
			weightIcon,
			TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
			{ ImageColor3 = bgColor }
		)
		:Play()
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
	-- print(`Slot {slotIndex} selected`)
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

	self:RefreshLoadoutSelection()
	self:SetupRenderConnect()
	showScreen()

	if self.walkOnAnimation then
		self.walkOnAnimation:Play()
	end

	if self.mainFrame then
		self.mainFrame.Visible = true
	end

	self.mainFrame:TweenPosition(
		UDim2.new(0.5, 0, 0.5, 0),
		Enum.EasingDirection.Out,
		Enum.EasingStyle.Quad,
		0.5,
		true,
		function()
			self.isShowing = false
		end
	)
end

function LoadoutUI:Hide(exitting: boolean?, destroyAfterFade: boolean?)
	self.alive = false

	local loadoutName = self.activeLoadoutName
	if loadoutName and loadoutName ~= "" and loadoutName ~= "Custom" then
		finalRequestLoadout(loadoutName)
	else
		finalRequestLoadout("Default")
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

	for _, sound in pairs(self.sounds) do
		sound:Destroy()
	end

	if self.mainFrame and self.mainFrame.Parent then
		self.mainFrame:Destroy()
	end
	if self.loadoutCharacter and self.loadoutCharacter.Parent then
		self.loadoutCharacter:Destroy()
	end
end

return LoadoutUI
