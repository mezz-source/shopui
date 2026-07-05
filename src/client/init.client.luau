local ReplicatedStorage = game:GetService("ReplicatedStorage")
local uis = game:GetService("UserInputService")
local SLSGui = require(ReplicatedStorage.ShopClient.UI.SLSGui)

ReplicatedStorage.Datastore.LoadClientData:FireServer()

local activeSLSGui

uis.InputBegan:Connect(function(obj, ev)
	if ev then
		return
	end
	if game.Players.LocalPlayer:GetAttribute("InShop") then
		return
	end

	if obj.KeyCode == Enum.KeyCode.E then
		activeSLSGui = SLSGui.new({
			shopModelName = "TestShop",
			startState = "Shop",
		})
		activeSLSGui:Start("Shop")
	elseif obj.KeyCode == Enum.KeyCode.Q then
		activeSLSGui = SLSGui.new({
			shopModelName = "TestShop2",
			startState = "Shop",
		})
		activeSLSGui:Start("Shop")
	end
end)
