local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local LocalPlayer = Players.LocalPlayer

local Zone = require(ReplicatedStorage.Zone.Zone)
local SLSGui = require(ReplicatedStorage.ShopClient.UI.SLSGui)

local Shops = workspace:WaitForChild("Shops")

ReplicatedStorage.Datastore.LoadClientData:FireServer()

local playerModule = require(LocalPlayer.PlayerScripts:WaitForChild("PlayerModule"))
local controls = playerModule:GetControls()

local isInShop = false
local canEnterShop = true

local ENTER_DELAY = 0.5

local function setMovementEnabled(enabled: boolean)
	if enabled then
		controls:Enable()
	else
		controls:Disable()
	end
end

local function startEntryCooldown(duration: number)
	canEnterShop = false

	task.delay(duration, function()
		canEnterShop = true
	end)
end

local function leaveShop()
	isInShop = false

	setMovementEnabled(true)
	startEntryCooldown(5)
end

local function enterShop(shopModel: Model)
	isInShop = true
	canEnterShop = false

	setMovementEnabled(false)

	local shop = SLSGui.new({
		shopModelName = shopModel.Name,
		startState = "Shop",
	})

	shop:Start("Shop")
end

local function onCharacterEntered(zone, shopModel)
	if not LocalPlayer.Character or LocalPlayer.Character ~= LocalPlayer.Character then
		return
	end

	if isInShop or not canEnterShop then
		return
	end

	task.wait(ENTER_DELAY)

	if isInShop then
		return
	end

	if not zone:CharacterPresent(LocalPlayer.Character) then
		return
	end

	enterShop(shopModel)
end

local function loadShops()
	repeat
		task.wait()
	until #Shops:GetChildren() >= 2

	for _, shopModel in Shops:GetChildren() do
		local trigger = shopModel:WaitForChild("Trigger")
		local zone = Zone.new(trigger)

		zone.CharacterEntered:Connect(function(character)
			if character ~= LocalPlayer.Character then
				return
			end

			if isInShop or not canEnterShop then
				return
			end

			task.wait(0.5)

			if isInShop then
				return
			end

			if zone:CharacterPresent(LocalPlayer.Character) then
				enterShop(shopModel)
			end
		end)
	end
end

LocalPlayer.AttributeChanged:Connect(function(attribute)
	if attribute ~= "InShop" then
		return
	end

	if not LocalPlayer:GetAttribute("InShop") then
		leaveShop()
	end
end)

loadShops()
