--[[------------------------------------------------------------------------------------
   	
   DATASTORE P-MANAGER
   
   @module MANAGER
   @author mezz_inc
   @description Handles saving, and creation of player data on join & leave
   
   @within ServerScriptService/DataAPI
   
   
   Initialization
   
]]
------------------------------------------------------------------------------------

local Module = {}

--- Name of the module
local NAME: string = "Manager"

--- We are not getting the datastore for actual use, just for quickly migrating old data
local DataStoreService = game:GetService("DataStoreService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DatastoreRem = ReplicatedStorage:WaitForChild("Datastore")
local Players = game:GetService("Players")

--- Access the Data API folder
local ServerScriptService = game:GetService("ServerScriptService")
local DataAPI = ServerScriptService:WaitForChild("DataAPI")

--- Old Datastores

local VERSION = "3.0v"

-- Datastores
local oldPlayerStatsDataStore = DataStoreService:GetDataStore("Data" .. VERSION, "Stats")

local oldPlayerPreferencesDataStore = DataStoreService:GetDataStore("Data" .. VERSION, "Preferences")

Module._meta = {
	name = NAME,
	version = "1.0.0",
	description = "Handles player data instancing and saving",
}

--[[----------------------------------------------------------------------------------

	Variables

]]
----------------------------------------------------------------------------------

--- The max amount of times to attempt to save a players data, if it fails
local SAVE_ATTEMPTS: number = 5
local LOAD_ATTEMPTS: number = 8

--- A list of IDs whose currently in the process of being loaded
--- Released after data folder is created
local loadQueued: { number } = {}

--- A list of number values that get copied to the player's leaderstats
--- when changed
local replicatedLeaderStatValues: { string } = { "Kills", "Deaths", "Level", "Credits" }

--[[----------------------------------------------------------------------------------

	Modules

]]
----------------------------------------------------------------------------------

--- Dependant modules
local Debug = require(DataAPI.Debug)
local Types = require(DataAPI.Types)
local Schema = require(DataAPI.Schema)
local Core = require(DataAPI.Core)
local API = require(DataAPI.API)

local ErrorModule = require(DataAPI.ErrorTypes)

--[[----------------------------------------------------------------------------------

	Types

]]
----------------------------------------------------------------------------------

type ErrorType = Types.ErrorType
type Store = Types.Store
type AllowedStoreTypes = Types.AllowedStoreTypes
type ValidStores = Types.ValidStores
type ValidDatastoreEntryTypes = Types.ValidDatastoreEntryTypes

--[[----------------------------------------------------------------------------------

	Debug
	Mostly wrapper functions for the Debug module

]]
----------------------------------------------------------------------------------

--- The source name of the module for debugging
local SOURCE_NAME: string = `[DataAPI.{NAME}]`

--- Prints out a debug message if debug is enabled
--- @param ... any? a variable number of arguments to prin
local function debugPrint(...)
	Debug.debugPrint(SOURCE_NAME, ...)
end

--- Warn a statement to the output
--- @param ... string? a variable number of strings/types to print
local function debugWarn(...)
	Debug.debugWarn(SOURCE_NAME, ...)
end

--- Raise an error to the output
--- @param ... string? a variable number of strings/types to print
local function debugError(...)
	Debug.debugError(SOURCE_NAME, ...)
end

------------------------- Module

--[[----------------------------------------------------------------------------------

	Local Functions

]]
----------------------------------------------------------------------------------

--- Whether or not an entry exists for playerId
--- @param playerId number the id of the player to check
--- @return boolean exists whether the data exists
local function playerDataExists(playerId: number): boolean
	return Core.storeEntryExists("PlayerInfo", playerId)
end

--- Sets up the player's datastore entries
--- @param playerId number the id of the player to setup
local function setupPlayerData(playerId: number)
	local ORDERED_STORES = Core.getAllOrderedStores() :: { Store }
	local FLAT_STORES = Core.getAllFlatStores() :: { Store }
	local COLD_STORES = Core.getAllColdStores() :: { Store }

	local function ensureStoreEntry(store: Store, defaultValue: any)
		if Core.storeEntryExists(store.name, playerId) then
			return
		end

		Core.updateStoreEntry(store.name, playerId, defaultValue)
	end

	--- Set all numeral entries to zero
	for _, store: Store in ipairs(ORDERED_STORES) do
		ensureStoreEntry(store, 0)
	end

	for _, store: Store in ipairs(FLAT_STORES) do
		local storeName = store.name
		local scheme = Schema.getSchemaForStore(storeName) :: { [string]: ValidDatastoreEntryTypes }
		ensureStoreEntry(store, scheme)
	end

	for _, store: Store in ipairs(COLD_STORES) do
		local storeName = store.name
		local scheme = Schema.getSchemaForStore(storeName)
		ensureStoreEntry(store, scheme)
	end

	-- Ensure inventory schema/version migrations run during load, even before gameplay systems query inventory.
	API.getAllPlayerInventory(playerId)
end

--- Attempt to update all tables & ordered data stores
--- @param playerId number the id of the player to update
--- @return boolean success whether or not it saved successfully
local function attemptDataSave(playerId: number, playerDataFolder: Folder): boolean
	--- Get all the created stores so far

	--if true then
	--	if math.random(1,5) > 1 then
	--		return false
	--	end
	--end

	local flatDataFolder = playerDataFolder:WaitForChild("FlatData") :: Folder
	local orderedDataFolder = playerDataFolder:WaitForChild("OrderedData") :: Folder

	if not flatDataFolder or not orderedDataFolder then
		debugWarn("Malformed data folder - can't save")
		return false
	end

	for _, folder: Folder in ipairs(flatDataFolder:GetChildren()) do
		--- Gete data table from the instances
		local storeName = folder.Name
		local values = folder:GetChildren()
		local dataMap = Schema.instancesToTable(values)

		local store = Core.getStore(storeName) :: Store
		debugPrint("Saving store " .. store.name)

		--- Datastore accessor
		local success, result = store:SetEntry(playerId, dataMap)
		if not success then
			debugPrint("Could not save data store", storeName, "because", result)
			return false
		end
	end

	--- Save the ordered one
	for _, numberValue: NumberValue in ipairs(orderedDataFolder:GetChildren()) do
		local storeName = numberValue.Name
		local value = numberValue.Value

		local store = Core.getStore(storeName) :: Store

		debugPrint("Saving store " .. store.name)

		--- Datastore accessor
		local success, result = store:SetEntry(playerId, value)
		if not success then
			debugPrint("Could not save data store", storeName, "because", result)
			return false
		end
	end

	return true
end

--- Attempts (several times if failure) to save all player data
--- @param Player Player the player to save data for
local function savePlayerData(Player: Player)
	local userId = Player.UserId
	local data = Player:FindFirstChild("Data") :: Folder

	if not data then
		debugWarn("Player had no data folder to save in the first place - coward")
		return
	end

	--- If for some reason the player dissapears we won't forget what their data is, we clean it later
	local playerDataFolder = data:Clone()

	debugPrint("Saving player data " .. tostring(Player) .. " - remembered their data folder")

	task.spawn(function()
		local success = false
		for attempt = 1, SAVE_ATTEMPTS do
			debugPrint("Attempt", attempt)
			if attemptDataSave(userId, playerDataFolder) then
				debugPrint(`Successfully saved data for {Player.Name}`)
				success = true
				break
			end

			local waitTime = math.pow(2, attempt) * 0.2 -- 0.2s, 0.4s, 0.8s, etc.
			debugWarn(`Attempt {attempt} failed to save data for {Player.Name}, retrying in {waitTime} seconds`)
			task.wait(waitTime)
		end

		if success then
			return
		end
		debugError(`All attempts failed to save data for {Player.Name}`)
		playerDataFolder:Destroy() -- sound scary but dont panic
	end)
end

--- Attempts to read and insert the values from the player's datastores
--- @userId number the user's id
local function attemptLoadPlayerData(userId: number)
	--- Check first to make sure the player has data to begin with
	setupPlayerData(userId)

	local Player = Players:GetPlayerByUserId(userId)
	if not Player then
		return false
	end

	--- Make the overhead data holder for all the instances
	local DataFolder = Instance.new("Folder", Player)
	DataFolder.Name = "Data"

	--- Get all the created stores so far
	local ORDERED_STORES = Core.getAllOrderedStores() :: { Store }
	local FLAT_STORES = Core.getAllFlatStores() :: { Store }

	--- Create the holder for table-like data stores
	local flatFolder = Instance.new("Folder", DataFolder)
	flatFolder.Name = "FlatData"

	--- Create the holder for number value stores
	local orderedDataFolder = Instance.new("Folder", DataFolder)
	orderedDataFolder.Name = "OrderedData"

	--- Make basic number values
	for _, store: Store in ipairs(ORDERED_STORES) do
		local name = store.name

		debugPrint("Loading ordered store", name)
		local success, result = store:GetEntry(userId)
		if not success then
			debugWarn(`Unable to load the store {name}! {result}`)
			return false
		end

		local newIntegerValue = Instance.new("NumberValue", orderedDataFolder)
		newIntegerValue.Name = name
		newIntegerValue.Value = result
	end

	--- Load each table-based store
	for _, store: Store in ipairs(FLAT_STORES) do
		local name = store.name

		debugPrint("Loading flat store", name)

		local entrySucces, result = store:GetEntry(userId)
		if not entrySucces then
			debugWarn(`Unable to load the store {name}! {result}`)
			return false
		end
		-- result result is the players key pair
		local scheme = Schema.getSchemaForStore(name)

		--- Construct a template
		local schemeFolder: Folder
		local success, resultFolder = pcall(function()
			schemeFolder = Schema.constructFolderFromEntryTable(name, scheme) :: Folder
		end)

		if not success then
			debugWarn(`Unable to create the folder for the store {name}! {resultFolder}`)
			continue
		end

		--- Had to implement a fix for adding values later on.

		--- For each value in the scheme,
		--- check if the player has the same key as the name
		--- That means they HAVE saved data for it, so let's copy it over
		local values = schemeFolder:GetChildren()
		for _, value in ipairs(values) do
			local valueName = value.Name

			--- An entry exists for this name
			if result[valueName] ~= nil then
				value.Value = result[valueName]
			else
				debugWarn("It looks like player didn't have " .. valueName .. " - well, now they do!")
			end
		end

		--- Any other name will be ignore
		schemeFolder.Parent = flatFolder
	end
	debugPrint("Instanced all player data successfully")
	return true
end

local function migrateOldData(Player: Player)
	local success, result = pcall(function()
		return oldPlayerStatsDataStore:GetAsync("Player_" .. Player.UserId)
	end)

	if not success or not result then
		debugPrint("Player " .. Player.Name .. " likely had no old data to catch")
		return
	end

	debugPrint("Found old data for " .. Player.Name .. ", attempting data migration")

	local dataList = {
		["Kills"] = result["Kills"],
		["Deaths"] = result["Deaths"],
		["Experience"] = result["Experience"],
		["Level"] = result["Level"],
		["Completion"] = result["Completion"],
	}

	for key, value in pairs(dataList) do
		if value ~= nil then
			local ok = API.setPlayerInfo(Player, key, value)
			if not ok then
				debugWarn(`Could not update player info {key} to {value} during migration!`)
			end
		end
	end

	local prefSuccess, prefResult = pcall(function()
		return oldPlayerPreferencesDataStore:GetAsync("Player_" .. Player.UserId)
	end)

	if not prefSuccess or not prefResult then
		debugWarn("No old preferences found for " .. Player.Name)
		return
	end

	local prefList = {
		["SunRays"] = prefResult["SunRays"],
		["CameraSway"] = prefResult["CameraSway"],
		["Materials"] = prefResult["Materials"],
		["DoomMusic"] = prefResult["Shadows"],
		["ShowDamageAmount"] = prefResult["ShowDamageAmount"],
		["HealthBars"] = prefResult["ShowHealthbars"],
		["DepthOfField"] = prefResult["DepthOfField"],
		["KillFeed"] = prefResult["KillFeed"],
		["Shadows"] = prefResult["Shadows"],
	}

	for key, value in pairs(prefList) do
		if value ~= nil then
			local ok = API.setPlayerPreference(Player, key, value)
			if not ok then
				debugWarn(`Could not update preference {key} to {value} during migration!`)
			end
		end
	end
end

--- Setups & creates a clone of certain stats for a player
--- and displays their leaderstats
--- @param Player Player the player to add stats to
--- @param dataFolder Folder the player's fully loaded datafolder
local function setupPlayerLeaderStats(Player: Player, dataFolder: Folder)
	local existingStats = Player:FindFirstChild("leaderstats")
	if existingStats then
		debugWarn("Er... why do they already have leaderstats 😨")
		return
	end

	local newStats = Instance.new("Folder", Player)
	newStats.Name = "leaderstats"

	for _, leaderStatValue in ipairs(replicatedLeaderStatValues) do
		local statValue = dataFolder:FindFirstChild(leaderStatValue, true)
		if not statValue or not statValue:IsA("NumberValue") then
			debugWarn(`{statValue} must be an existing number value in the player's data folder`)
			continue
		end

		debugPrint("Replicated value", leaderStatValue, "to leaderstat")

		local newNumberValue = Instance.new("NumberValue", newStats)
		newNumberValue.Name = leaderStatValue
		newNumberValue.Value = statValue.Value
		local updateConnection: RBXScriptConnection

		--- Whenever the player's data is updated in-server
		updateConnection = statValue.Changed:Connect(function()
			if not statValue or not newNumberValue then
				updateConnection:Disconnect()
				return
			end

			newNumberValue.Value = statValue.Value
		end)
	end
end

--- Loads the data folder for the player in the server
--- @param Player Player the player to load the data for
local function loadPlayerData(Player: Player)
	-- If you have a data folder you're already loaded
	if Player:FindFirstChild("Data") then
		return
	end

	if table.find(loadQueued, Player.UserId) then
		return
	end

	table.insert(loadQueued, Player.UserId)

	if not Core.isLoaded() then
		print("Yielding for Core to load before attempting to create data")
		while not Core.isLoaded() do
			task.wait(0.5)
		end
	end

	local userId = Player.UserId

	task.spawn(function()
		local success = false
		for attempt = 1, LOAD_ATTEMPTS do
			--- i mean what do you want me to do you left before we even got started
			if not Player then
				success = true
				break
			end

			debugPrint("Attempt", attempt)

			if attemptLoadPlayerData(userId) then
				debugPrint(`Successfully loaded data for {Player.Name}`)
				DatastoreRem.DataLoaded:FireClient(Player)
				success = true
				break
			end

			local Data = Player:FindFirstChild("Data")
			if Data then
				Data:Destroy()
			end

			local waitTime = math.pow(2, attempt) * 0.2 -- 0.2s, 0.4s, 0.8s, etc.
			debugWarn(`Attempt {attempt} failed to load data for {Player.Name}, retrying in {waitTime} seconds`)
			task.wait(waitTime)
		end

		if table.find(loadQueued, Player.UserId) then
			table.remove(loadQueued, table.find(loadQueued, Player.UserId))
		end

		if success then
			if not Player then
				return
			end

			local data = Player:FindFirstChild("Data")
			if not data then
				return
			end

			--- Setup leader stats
			if Player then
				setupPlayerLeaderStats(Player, data)
			end

			--- Check if not migrated yet
			if not API.getPlayerFlag(Player, "OldDataMigrated") then
				-- This won't do anything unless they have old data in the first place
				migrateOldData(Player)

				--- Prevents this from tripping later
				API.setPlayerFlag(Player, "OldDataMigrated", true)
				warn("Migrated data")
			end

			return
		end
		Player:Kick(
			"For some reason, the datastore service left me on read! probably just means its down OR the games too popular. hopefully the later, try again later (your data is probably fine just in a dusty box)"
		)
		debugError(`All attempts to load data for {Player.Name} failed`)
	end)
end

local function playerLeft(Player: Player)
	savePlayerData(Player)
end

--[[----------------------------------------------------------------------------------

	Start & Test Features

]]
----------------------------------------------------------------------------------

--- Initalization function
local function start()
	debugPrint("Module is ready")
end

--- Runs a developer test on the module
local function test()
	debugWarn("Something has gone awry!")

	task.wait(2)

	--- do something risky
	local success, result = pcall(function()
		error(ErrorModule.new("GetFailure", "gaslight vibes"))
	end)

	if not success and getmetatable(result) == ErrorModule then
		debugError("Looks like one of ours!", result)
	end
end

--[[----------------------------------------------------------------------------------

	CONNECTIONS

]]
----------------------------------------------------------------------------------

local DatastoreEvents = ReplicatedStorage:WaitForChild("Datastore")
local LoadClientData = DatastoreEvents:WaitForChild("LoadClientData")
LoadClientData.OnServerEvent:Connect(loadPlayerData)

--- Save all player data
game:BindToClose(function()
	for _, Player in Players:GetPlayers() do
		savePlayerData(Player)
	end
end)

Players.PlayerRemoving:Connect(playerLeft)

--[[----------------------------------------------------------------------------------

	END

]]
----------------------------------------------------------------------------------

--- Calling module.start() will start the module
--- Calling module.test() will test a function of the module
Module.start = start
Module.test = test

return Module
