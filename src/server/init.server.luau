local ServerScriptService = game:GetService("ServerScriptService")
local ShopServer = ServerScriptService.ShopServer
local Queries = require(ShopServer.Queries)
local Purchases = require(ShopServer.Purchases)
local Loadouts = require(ShopServer.Loadouts)

local function load()
	print("Loaded shop server system")
	Queries.load()
	Purchases.load()
	Loadouts.load()
end

load()
