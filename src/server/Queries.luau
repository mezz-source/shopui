local Queries = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local ItemInfo = ServerStorage.ShopStorage:WaitForChild("ItemInfo")
local ShopTypes = require(ReplicatedStorage.ShopClient.ShopTypes)
local ShopRemotes = ReplicatedStorage:WaitForChild("ShopRemotes")
local ShopBindables = ServerStorage.ShopBindables

local DataAPI = require(game.ServerScriptService.DataAPI.API)

local MODULE_INFOS: { [string]: {} } = {}
local MODULES_BY_CATEGORY: { [string]: { [string]: {} } } = {}

type Category = ShopTypes.Category
type Weight = ShopTypes.Weight
type Pill = ShopTypes.Pill
type FilterInfo = ShopTypes.FilterInfo
type ShopInfo = ShopTypes.ShopInfo
type ArmorInfo = ShopTypes.ArmorInfo
type MeleeInfo = ShopTypes.MeleeInfo
type GunInfo = ShopTypes.GunInfo
type WeaponInfo = ShopTypes.WeaponInfo
type Query = ShopTypes.ShopQuery

local function normalizeLower(value: string?): string
	if type(value) ~= "string" then
		return ""
	end
	return string.lower(value)
end

local function matchesWeight(info: WeaponInfo, weightsQuery: Weight | { Weight }?): boolean
	if weightsQuery == nil then
		return true
	end

	if type(weightsQuery) == "string" then
		return info.Weight == weightsQuery
	end

	if type(weightsQuery) == "table" then
		for _, allowedWeight in ipairs(weightsQuery) do
			if info.Weight == allowedWeight then
				return true
			end
		end
		return false
	end

	return true
end

local function getSortValue(info: WeaponInfo, sortBy: string): any
	if string.sub(sortBy, 1, 9) == "ItemInfo." then
		local itemInfoKey = string.sub(sortBy, 10)
		local itemInfo = info.ItemInfo
		if type(itemInfo) == "table" then
			return itemInfo[itemInfoKey]
		end
		return nil
	end

	return (info :: any)[sortBy]
end

local function projectInfo(info: WeaponInfo, fields: { string }?): { [string]: any }
	if fields == nil or #fields == 0 then
		return info :: any
	end

	local projected: { [string]: any } = {}
	for _, key in ipairs(fields) do
		if string.sub(key, 1, 9) == "ItemInfo." then
			local itemInfoKey = string.sub(key, 10)
			projected.ItemInfo = projected.ItemInfo or {}
			local itemInfo = info.ItemInfo
			if type(itemInfo) == "table" then
				projected.ItemInfo[itemInfoKey] = itemInfo[itemInfoKey]
			end
		else
			projected[key] = (info :: any)[key]
		end
	end

	return projected
end

local function passesBaseFilters(info: WeaponInfo, query: Query): boolean
	if not matchesWeight(info, query.weights) then
		return false
	end

	if query.nameContains then
		local target = normalizeLower(query.nameContains)
		if not string.find(normalizeLower(info.Name), target, 1, true) then
			return false
		end
	end

	if query.search then
		local target = normalizeLower(query.search)
		local nameMatches = string.find(normalizeLower(info.Name), target, 1, true) ~= nil
		local loreMatches = string.find(normalizeLower(info.Lore), target, 1, true) ~= nil
		if not (nameMatches or loreMatches) then
			return false
		end
	end

	if query.priceMin and info.Price < query.priceMin then
		return false
	end

	if query.priceMax and info.Price > query.priceMax then
		return false
	end

	if query.levelMin and info.Level < query.levelMin then
		return false
	end

	if query.levelMax and info.Level > query.levelMax then
		return false
	end

	if query.consumable ~= nil and info.Consumable ~= query.consumable then
		return false
	end

	if query.groupUnlocked ~= nil and info.GroupUnlocked ~= query.groupUnlocked then
		return false
	end

	if query.customFilters then
		for key, expectedValue in pairs(query.customFilters) do
			if string.sub(key, 1, 9) == "ItemInfo." then
				local itemInfo = info.ItemInfo
				local itemInfoKey = string.sub(key, 10)
				if type(itemInfo) ~= "table" or itemInfo[itemInfoKey] ~= expectedValue then
					return false
				end
			elseif (info :: any)[key] ~= expectedValue then
				return false
			end
		end
	end

	return true
end

local TYPE_RANK = {
	number = 1,
	string = 2,
	boolean = 3,
	table = 4,
	userdata = 5,
	thread = 6,
	["function"] = 7,
	["nil"] = 99,
}

local function normalizeSortKey(value: any): (number, number?, string?)
	if type(value) == "number" and value ~= value then
		value = nil
	end

	local valueType = type(value)
	local rank = TYPE_RANK[valueType] or 98

	if valueType == "number" then
		return rank, value, nil
	end

	if valueType == "string" then
		return rank, nil, string.lower(value)
	end

	if valueType == "boolean" then
		return rank, value and 1 or 0, nil
	end

	if valueType == "nil" then
		return rank, nil, nil
	end

	return rank, nil, tostring(value)
end

local function applySort(infos: { WeaponInfo }, query: Query)
	local sortBy = query.sortBy or "Name"
	local direction = query.sortDir == "desc" and -1 or 1

	local decorated = {}
	for i, info in ipairs(infos) do
		local rank, numberKey, stringKey = normalizeSortKey(getSortValue(info, sortBy))
		table.insert(decorated, {
			index = i,
			name = info.Name,
			rank = rank,
			numberKey = numberKey,
			stringKey = stringKey,
			info = info,
		})
	end

	table.sort(decorated, function(a, b)
		if a.rank ~= b.rank then
			if direction == 1 then
				return a.rank < b.rank
			end
			return a.rank > b.rank
		end

		if a.numberKey ~= b.numberKey then
			if direction == 1 then
				return (a.numberKey :: number) < (b.numberKey :: number)
			end
			return (a.numberKey :: number) > (b.numberKey :: number)
		end

		if a.stringKey ~= b.stringKey then
			if direction == 1 then
				return (a.stringKey :: string) < (b.stringKey :: string)
			end
			return (a.stringKey :: string) > (b.stringKey :: string)
		end

		if a.name ~= b.name then
			return a.name < b.name
		end

		return a.index < b.index
	end)

	for i, row in ipairs(decorated) do
		infos[i] = row.info
	end
end

local function applyPagination(infos: { WeaponInfo }, query: Query): { WeaponInfo }
	local offset = math.max(0, math.floor(query.offset or 0))
	local limit = query.limit and math.max(0, math.floor(query.limit)) or nil
	local startIndex = offset + 1
	local endIndex = limit and math.min(#infos, startIndex + limit - 1) or #infos

	local output: { WeaponInfo } = {}
	for i = startIndex, endIndex do
		local value = infos[i]
		if value ~= nil then
			table.insert(output, value)
		end
	end

	return output
end

local function toResultShape(infos: { WeaponInfo }, query: Query?, defaultReturnType: "map" | "array")
	local returnType = defaultReturnType
	if query and query.returnType then
		returnType = query.returnType
	end

	if returnType == "map" then
		local mapped: { [string]: any } = {}
		for _, info in ipairs(infos) do
			mapped[info.Name] = projectInfo(info, query and query.fields or nil)
		end
		return mapped
	end

	local output: { any } = {}
	for _, info in ipairs(infos) do
		table.insert(output, projectInfo(info, query and query.fields or nil))
	end
	return output
end

local function getInfo(moduleName: string): WeaponInfo?
	local cached = MODULE_INFOS[moduleName]
	if cached then
		return cached :: WeaponInfo
	end

	local moduleScript = ItemInfo:FindFirstChild(moduleName)
	if not moduleScript then
		warn("Module not found: " .. moduleName)
		return nil
	end

	local info = require(moduleScript) :: WeaponInfo
	if type(info) ~= "table" or type(info.Category) ~= "string" or type(info.Name) ~= "string" then
		warn("Invalid weapon module schema for: " .. moduleName)
		return nil
	end

	MODULE_INFOS[moduleName] = info
	if not MODULES_BY_CATEGORY[info.Category] then
		MODULES_BY_CATEGORY[info.Category] = {}
	end
	MODULES_BY_CATEGORY[info.Category][moduleName] = info

	return info
end

local function queryCategory(category: string, query: Query?): any
	local byCategory = MODULES_BY_CATEGORY[category]
	if not byCategory then
		return {}
	end

	local filtered: { WeaponInfo } = {}
	for _, info in pairs(byCategory) do
		if not query or passesBaseFilters(info :: WeaponInfo, query) then
			table.insert(filtered, info :: WeaponInfo)
		end
	end

	if query then
		applySort(filtered, query)
		filtered = applyPagination(filtered, query)
	end

	local defaultReturnType = query and "array" or "map"
	return toResultShape(filtered, query, defaultReturnType)
end

local function normalizeInvokeArgs(firstArg: any, secondArg: any, thirdArg: any): (any, any)
	if typeof(firstArg) == "Instance" and (firstArg :: Instance):IsA("Player") then
		return secondArg, thirdArg
	end

	return firstArg, secondArg
end

local function getWeaponInfo(weaponNameOrQuery: any, maybeQuery: Query?)
	local weaponName: string? = nil
	local query: Query? = nil

	if type(weaponNameOrQuery) == "string" then
		weaponName = weaponNameOrQuery
		query = maybeQuery
	elseif type(weaponNameOrQuery) == "table" then
		local q = weaponNameOrQuery :: Query
		query = q
		weaponName = q.name
	end

	if not weaponName then
		warn("no first param")
		return nil
	end

	local info = getInfo(weaponName)
	if not info then
		warn("no info")
		return nil
	end

	if query and query.fields and #query.fields > 0 then
		local result = projectInfo(info, query.fields)
		print(result)
		return result
	end

	return info
end

local function getOwnedItems(player: Player): { string }
	local ownedItems = DataAPI.getPlayerOwnedItems(player)
	if not ownedItems then
		return {}
	end
	return ownedItems
end

local function getWeaponInfoInvoke(firstArg: any, secondArg: any, thirdArg: any)
	local weaponNameOrQuery, maybeQuery = normalizeInvokeArgs(firstArg, secondArg, thirdArg)
	return getWeaponInfo(weaponNameOrQuery, maybeQuery)
end

local function getAllInfoForCategory(categoryOrQuery: any, maybeQuery: Query?)
	local category: string? = nil
	local query: Query? = nil

	if type(categoryOrQuery) == "string" then
		category = categoryOrQuery
		query = maybeQuery
	elseif type(categoryOrQuery) == "table" then
		local q = categoryOrQuery :: Query
		query = q
		category = q.category
	end

	if not category then
		return {}
	end

	return queryCategory(category, query)
end

local function getAllInfoForCategoryInvoke(firstArg: any, secondArg: any, thirdArg: any)
	local categoryOrQuery, maybeQuery = normalizeInvokeArgs(firstArg, secondArg, thirdArg)
	return getAllInfoForCategory(categoryOrQuery, maybeQuery)
end

local function getGunSettings(gunName: string): ShopTypes.GunSettings?
	local Item = ReplicatedStorage.WeaponPreview:FindFirstChild(gunName)
	if not Item then
		warn("Gun not found: " .. gunName)
		return nil
	end

	local Setting = Item:FindFirstChild("Setting")
	if not Setting then
		warn("Settings not found for gun: " .. gunName)
		return nil
	end

	return require(Setting)
end

local function getMeleeSettings(meleeName: string): ShopTypes.MeleeInfo?
	local Item = ReplicatedStorage.WeaponPreview:FindFirstChild(meleeName)
	if not Item then
		warn("Melee weapon not found: " .. meleeName)
		return nil
	end

	local Config = Item:FindFirstChild("Configuration")
	if not Config then
		warn("Configuration not found for melee weapon: " .. meleeName)
		return nil
	end

	local infoTable = {}

	for _, child in ipairs(Config:GetChildren()) do
		if child:IsA("ValueBase") then
			infoTable[child.Name] = child.Value
		end
	end

	return infoTable
end

local function getGunSettingInvoke(_, firstArg: any)
	return getGunSettings(firstArg)
end

local function getMeleeSettingsInvoke(_, firstArg: any)
	return getMeleeSettings(firstArg)
end

function Queries.load()
	for _, module in ipairs(ItemInfo:GetChildren()) do
		getInfo(module.Name)
	end

	ShopRemotes.GetWeaponInfo.OnServerInvoke = getWeaponInfoInvoke
	ShopRemotes.GetAllInfoForCategory.OnServerInvoke = getAllInfoForCategoryInvoke
	ShopRemotes.GetOwnedItems.OnServerInvoke = getOwnedItems
	ShopRemotes.GetGunSettings.OnServerInvoke = getGunSettingInvoke
	ShopRemotes.GetMeleeSettings.OnServerInvoke = getMeleeSettingsInvoke

	ShopBindables.GetPlayerOwnedItems.OnInvoke = getOwnedItems
	ShopBindables.GetWeaponInfo.OnInvoke = getWeaponInfoInvoke
	ShopBindables.GetAllInfoForCategory.OnInvoke = getAllInfoForCategoryInvoke
end

return Queries
