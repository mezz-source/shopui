local ReplicatedStorage = game:GetService("ReplicatedStorage")
local uis = game:GetService("UserInputService")
local shop = require(ReplicatedStorage.ShopClient.UI.Shop)

uis.InputBegan:Connect(function(obj, ev)
	if ev then
		return
	end
	if game.Players.LocalPlayer:GetAttribute("InShop") then
		return
	end

	if obj.KeyCode == Enum.KeyCode.E then
		shop.new("TestShop")
	end
end)
