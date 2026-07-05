--[[------------------------------------------------------------------------------------
   	
   DATASTORE API MODULE
   
   @module API
   @author mezz_inc
   @description Provides the toplevel control for the dataAPI system
   
   @within ServerScriptService/DataAPI
   
   
   Initialization
   
]]
------------------------------------------------------------------------------------

local Module = {}

--- Name of the module
local NAME: string = "API"

local Players = game:GetService("Players")

--- Access the Data API folder
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DatastoreRep = ReplicatedStorage:WaitForChild("Datastore")
local DataAPI = ServerScriptService:WaitForChild("DataAPI")

Module._meta = {
	name = NAME,
	version = "1.0.0",
	description = "Top-level control of the DataAPI with player-centric functionality",
}

--[[----------------------------------------------------------------------------------

	Modules

]]
----------------------------------------------------------------------------------

--- Dependant modules
local Core = require(DataAPI.Core)
local Debug = require(DataAPI.Debug)
local Types = require(DataAPI.Types)
local Schema = require(DataAPI.Schema)

--[[----------------------------------------------------------------------------------

	Types

]]
----------------------------------------------------------------------------------

export type ErrorType = Types.ErrorType
export type Store = Types.Store
export type ValidDatastoreEntryTypes = Types.ValidDatastoreEntryTypes
export type ValidDatastoreKey = Types.ValidDatastoreKey
export type ValidDatastoreValue = Types.ValidDatastoreValue
export type ValidPlayer = Types.ValidPlayer
export type ValidStores = Types.ValidStores
export type PlayerRank = Types.PlayerRanks

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
------------------------- Module

--[[----------------------------------------------------------------------------------

	LOCAL FUNCTIONS
	
]]
----------------------------------------------------------------------------------

local function yieldToLoad()
	--- not debug warn as this is for YOU buddy
	if not Core.isLoaded() then
		warn("Attempt to access the Data API too early - yielding until fully loaded")

		while not Core.isLoaded() do
			task.wait(0.5)
		end
	end
end

--- Returns whether a store should be served through the player's data folder.
--- @param storeName ValidStores the store to check
--- @return boolean served whether the store is hot-served
local function storeIsServed(storeName: ValidStores): boolean
	return Schema.isServedStore(storeName)
end

--- Checks if a player is in the server
--- @param playerId number the id of the player to check
--- @return boolean if the player is in the server
local function playerInServer(playerId: number): boolean
	if script:GetAttribute("pretendPlayersDontExist") then
		return false
	end
	local Player = Players:GetPlayerByUserId(playerId) :: Player?

	if Player then
		--- might as well get the datastore at this point, they're not even loaded
		local dataFolder = Player:FindFirstChild("Data")
		if not dataFolder then
			return false
		end
	end
	return Player ~= nil
end

--- Returns a safe UserId from a player
--- @param Player ValidPlayer the player to get the UserId of
--- @return number the UserId of the player
local function getSafeUserId(Player: ValidPlayer): number
	if type(Player) == "number" then
		return Player
	elseif typeof(Player) == "Instance" then
		if not Player:IsA("Player") then
			warn(`Provided argument cannot be converted into a UserId - Type: {Player.ClassName or "nil"}`)
			return 0
		else
			return Player.UserId
		end
	elseif typeof(Player) == "string" then
		--- Player username
		if Players:FindFirstChild(Player) then
			return Players[Player].UserId
		else
			--- Is an ID just a string
			local isNumber = tonumber(Player)
			if not isNumber then
				warn(`Provided string argument cannot be converted into a UserId or username - {Player}`)
				return 0
			else
				return isNumber
			end
		end
	else
		warn(`Provided argument cannot be converted into a UserId - Type: {typeof(Player)}`)
		return 0
	end
end

--- Returns the store object from the store name
--- @param Player ValidPlayer the player to get the UserId of
--- @param storeName ValidStores the name of the store to get
--- @return entry ValidDatastoreEntryTypes the data
local function getPlayerEntry(Player: ValidPlayer, storeName: ValidStores)
	local store = Core.getStore(storeName)
	local playerId = getSafeUserId(Player)
	local _, result = store:GetEntry(playerId)
	return result
end

--- Overwrites a player's data for a storename entirely - primarily used for ordered datastores
--- Avoid using for flat stores
--- @param Player ValidPlayer the player to get the UserId of
--- @param storeName ValidStores the name of the store to set the data in
--- @param newData any the data to set the store to
--- @return success boolean whether it was able to be done
local function setPlayerEntry(Player: ValidPlayer, storeName: ValidStores, newData: any): boolean
	local store = Core.getStore(storeName)
	local playerId = getSafeUserId(Player)
	return store:SetEntry(playerId, newData)
end

--- Sets a new value for a key in a store
--- @param Player ValidPlayer the player to get the UserId of
--- @param storeName ValidStores the name of the store to set the data in
--- @param dataKey string the key of the data to set
--- @param newDataValue any the value to set the key to
--- @return success boolean whether it succeded
local function setPlayerEntryData(
	Player: ValidPlayer,
	storeName: ValidStores,
	dataKey: string,
	newDataValue: ValidDatastoreValue
): boolean
	local playerId = getSafeUserId(Player)
	local store = Core.getStore(storeName)
	local entry = getPlayerEntry(playerId, storeName)

	if not entry then
		warn(`Missing store name or key. Key: {playerId}, storeName: {storeName}`)
		return false
	end

	if entry[dataKey] == nil then
		warn(`Key {dataKey} is not a valid key for the entry`)
		return false
	end

	entry[dataKey] = newDataValue
	return store:SetEntry(playerId, entry) :: boolean
end

--- Attempts to increment a datastore value
--- @param Player ValidPlayer the player to get the UserId of
--- @param storeName ValidStores the name of the store to set the data in
--- @param dataKey string the key of the data to increment
--- @param incrementAmount number the amount to increment by
--- @return currentNumber number the current value of the datastore or 0 if failed
local function incrementPlayerEntryData(
	Player: ValidPlayer,
	storeName: ValidStores,
	dataKey: string,
	incrementAmount: number
): number
	local playerId = getSafeUserId(Player)
	local store = Core.getStore(storeName)
	local entry = getPlayerEntry(playerId, storeName)

	if entry[dataKey] == nil then
		warn(`Key {dataKey} is not a valid key for the entry`)
		return 0
	end

	-- Verify this is a number first of all
	local result = entry[dataKey]
	if type(result) ~= "number" then
		warn(`Attempt to increment key {dataKey} even though it's not a number - no change done`)
		return 0
	end

	local currentAmount = result + incrementAmount
	entry[dataKey] = currentAmount

	local success = store:SetEntry(playerId, entry)
	if not success then
		return 0
	end

	return currentAmount
end

--[[----------------------------------------------------------------------------------

	LIVE STATS
	Frequently updated information (lingo being stat)
	Stats should not constantly write to datastores when changed, so it's done
	via instances instead
	
]]
----------------------------------------------------------------------------------

--- Attempts to retrieve a player's Data folder in their player instance
--- Player must be in server
--- @param userId number the id of the player to get the folder of
--- @return DataFolder Folder the Data folder of the player
local function getPlayerDataFolder(userId: number): Folder?
	local Player = Players:GetPlayerByUserId(userId)
	if not Player then
		warn(`Provided ID {userId} is not in the server or not fully loaded`)
		return nil
	end

	local Data = Player:FindFirstChild("Data") :: Instance?
	return Data
end

--- Attempts to get a store folder from a player's Data folder
--- @param userId number the id of the player to get the folder of
--- @param storeName ValidStores the name of the store to get
--- @return store Folder the store folder
local function getPlayerDataFolderStore(userId: number, storeName: ValidStores): Folder?
	local dataFolder = getPlayerDataFolder(userId)
	if not dataFolder then
		warn("Could not get the data folder for provided player:", userId)
		return nil
	end

	local store = dataFolder:FindFirstChild(storeName, true)
	if not store then
		--- Early store access will yield
		for _ = 1, 4 do
			store = dataFolder:FindFirstChild(storeName, true)
			if store then
				return store
			end
			task.wait(1)
		end

		warn(`Could not find store name "{storeName}" in player's data folder`)
		return nil
	end

	return store
end

--- Attempts to get a stat instance from a player's Data folder
--- @param Player ValidPlayer a player id or object
--- @param storeName ValidStores the name of the store to get
--- @param statName string the name of the stat to get
--- @return stat ValueBase? the stat instance
local function getStatInstance(Player: ValidPlayer, storeName: ValidStores, statName: string): ValueBase | nil
	local userId = getSafeUserId(Player)

	local store = getPlayerDataFolderStore(userId, storeName) :: Folder?
	if not store then
		return nil
	end

	local statValue = store:FindFirstChild(statName) :: ValueBase?
	if not statValue then
		warn(`Could not find value "{statName}" in player's data folder for store {storeName}`)
		return nil
	end

	return statValue
end

--- Attempts to set a player's stat in the server
--- @param Player ValidPlayer a player id or object
--- @param storeName ValidStores the name of the store to get
--- @param statName string the name of the stat to set
--- @param statValue ValidDatastoreEntryTypes the value to set the stat to
--- @return success whether it succeded in changing the value
local function setPlayerStat(
	Player: ValidPlayer,
	storeName: ValidStores,
	statName: string,
	statValue: ValidDatastoreEntryTypes
): boolean
	local value = getStatInstance(Player, storeName, statName) :: ValueBase
	if not value then
		return false
	end
	value.Value = statValue
	return true
end

--- Adds a certain amount to a specific stat for a player in the server
--- @param Player ValidPlayer a player id or object
--- @param storeName ValidStores the name of the store to get
--- @param statName string the name of the stat to set
--- @param incrementNumber number the amount to add to the current stat value
--- @return amount number the new amount, 0 if not found
local function incrementPlayerStat(
	Player: ValidPlayer,
	storeName: ValidStores,
	statName: string,
	incrementNumber: number
): number
	local value = getStatInstance(Player, storeName, statName) :: ValueBase
	if not value then
		return 0
	end

	local newAmount = value.Value + incrementNumber
	value.Value = newAmount
	return newAmount
end

--[[----------------------------------------------------------------------------------

	NEWEST FUNCTIONS
	These are the data grabbers. Their main purpose is to check if the player
	we're trying to get the data of IS in the server.
	
	If they are in the server, we're going to check their stat folder, not their datastore.
	If they aren't, we do their datastore. Simple, no?
	
]]
----------------------------------------------------------------------------------

--- Returns the most recent store entry for a player
--- If the player shares the server with the current, it returns that store
--- Otherwise it returns the store from the datastore itself
--- @param Player ValidPlayer player id or object
--- @param storeName ValidStores the name of the store to get
local function getNewestEntry(Player: ValidPlayer, storeName: ValidStores)
	yieldToLoad()
	local userId = getSafeUserId(Player)
	local isInServer = playerInServer(userId)

	if isInServer then
		debugPrint(`Player {Player} is in the server - getting stat folder`)

		if not storeIsServed(storeName) then
			debugPrint(`Store {storeName} is cold-only - getting datastore`)
			return getPlayerEntry(Player, storeName)
		end

		local store = getPlayerDataFolderStore(userId, storeName)
		if not store then
			return getPlayerEntry(Player, storeName)
		end

		--- Ordered ones
		if not store:IsA("Folder") then
			return store.Value
		end

		local instances = store:GetChildren()
		--print(store, instances)
		return Schema.instancesToTable(instances)
	else
		debugPrint(`Player {Player} is not in the server - getting datastore`)

		--- Get datastore information
		return getPlayerEntry(Player, storeName)
	end
end

--- Attempts to update the most recent entry data for a player
--- If the player shares the server with the current, it updates their stat folder
--- Otherwise it updates the store in the datastore itself
--- @param Player ValidPlayer player id or object
--- @param storeName ValidStores the name of the store to get
--- @param keyName string the name of the key to update
--- @param newData any the new data to update the key with
--- @return success whether it was able to alter the data
local function updateNewestEntryData(Player: ValidPlayer, storeName: ValidStores, keyName: string, newData: any)
	yieldToLoad()

	local userId = getSafeUserId(Player)
	local isInServer = playerInServer(userId)
	local servedStore = storeIsServed(storeName)

	if isInServer and servedStore then
		debugPrint(`Player {Player} is in the server - updating stat folder`)

		--- Update stat information
		return setPlayerStat(Player, storeName, keyName, newData)
	else
		debugPrint(`Player {Player} is not in the server - updating datastore`)

		--- Update datastore information
		return setPlayerEntryData(Player, storeName, keyName, newData)
	end
end

--- Returns a specific piece of data from a player's most recent store
--- @param Player ValidPlayer player id or object
--- @param storeName ValidStores the name of the store to get
--- @param keyName string the name of the key to get
--- @return value any the value of the data if it exists
local function getNewestEntryData(Player: ValidPlayer, storeName: ValidStores, keyName: string)
	yieldToLoad()

	local tableEntry = getNewestEntry(Player, storeName)
	if not tableEntry then
		return nil
	end

	if tableEntry[keyName] == nil then
		debugWarn(`{keyName} is missing from the entry {storeName}`)
		return nil
	end

	return tableEntry[keyName]
end

--- Updates a number value in a player's most recent store
--- @param Player ValidPlayer player id or object
--- @param storeName ValidStores the name of the store to get
--- @param newData string the name of the key to update
--- @return success whether it was able to alter the data
local function updateNewestOrderedEntry(Player: ValidPlayer, storeName: ValidStores, newData: number): boolean
	yieldToLoad()

	local userId = getSafeUserId(Player)
	local isInServer = playerInServer(userId)

	if isInServer then
		debugPrint(`Player {Player} is in the server - updating stat folder`)

		local value = getPlayerDataFolderStore(userId, storeName)
		if not value or not value:IsA("ValueBase") then
			warn("No value for the ordered data was found - are you sure it IS an ordered data store?")
			return false
		end

		value.Value = newData

		return true
	else
		debugPrint(`Player {Player} is not in the server - updating datastore`)

		return setPlayerEntry(Player, storeName, newData)
	end
end

--- Increments a number value in a player's most recent store, 0 if failed
--- @param Player ValidPlayer player id or object
--- @param storeName ValidStores the name of the store to get
--- @param newAmount number the amount to increment the data by
--- @return amount number the new amount
local function incrementNewestOrderedEntry(Player: ValidPlayer, storeName: ValidStores, newAmount: number): number
	yieldToLoad()

	local userId = getSafeUserId(Player)
	local isInServer = playerInServer(userId)

	if isInServer then
		debugPrint(`Player {Player} is in the server - updating stat folder`)

		local value = getPlayerDataFolderStore(userId, storeName)
		if not value or not value:IsA("ValueBase") then
			warn("No value for the ordered data was found - are you sure it IS an ordered data store?")
			return 0
		end

		local curAmount = value.Value
		value.Value = curAmount + newAmount

		return value.Value
	else
		debugPrint(`Player {Player} is not in the server - updating datastore`)
		local Store = Core.getStore(storeName)
		local _, amount = Store:GetEntry(userId)
		setPlayerEntry(Player, storeName, amount + newAmount)
		return amount + newAmount
	end
end

--- Increments a players data from its newest entry and returns the new amount, 0 if failed
--- @param Player ValidPlayer the player to get the UserId of
--- @param storeName ValidStores the name of the store to get
--- @param keyName string the name of the key to increment
--- @param incrementAmount number the amount to increment the data by
--- @return newAmount number the new amount after incrementing
local function incrementNewestEntry(
	Player: ValidPlayer,
	storeName: ValidStores,
	keyName: string,
	incrementAmount: number
): number
	yieldToLoad()

	local userId = getSafeUserId(Player)
	local isInServer = playerInServer(userId)
	local servedStore = storeIsServed(storeName)

	if isInServer and servedStore then
		return incrementPlayerStat(Player, storeName, keyName, incrementAmount)
	else
		return incrementPlayerEntryData(Player, storeName, keyName, incrementAmount)
	end
end

--- Returns a table entry from a store when the entry is dictionary-shaped.
--- @param Player ValidPlayer a player id or object
--- @param storeName ValidStores the store to inspect
--- @return {[string]: ValidDatastoreValue}? tableEntry the table entry if it exists
local function getPlayerTableEntry(Player: ValidPlayer, storeName: ValidStores)
	if storeIsServed(storeName) then
		warn(`Store {storeName} is served and does not expose table-backed data`)
		return nil
	end

	local entry = getNewestEntry(Player, storeName)
	if type(entry) ~= "table" then
		warn(`Store {storeName} does not contain table data`)
		return nil
	end

	return entry
end

--- Sets an entire table entry in a cold store.
--- @param Player ValidPlayer a player id or object
--- @param storeName ValidStores the store to update
--- @param newTable {[string]: ValidDatastoreValue} the table to store
--- @return boolean success whether it was able to be done
local function setPlayerTableEntry(
	Player: ValidPlayer,
	storeName: ValidStores,
	newTable: { [string]: ValidDatastoreValue }
): boolean
	if storeIsServed(storeName) then
		warn(`Store {storeName} is served and cannot be replaced with a table entry`)
		return false
	end

	return setPlayerEntry(Player, storeName, newTable)
end

--- Returns a key from a table-backed store entry.
--- @param Player ValidPlayer a player id or object
--- @param storeName ValidStores the store to inspect
--- @param dataKey string the key to retrieve
--- @return ValidDatastoreValue? value the value if it exists
local function getPlayerTableEntryData(Player: ValidPlayer, storeName: ValidStores, dataKey: string)
	local entry = getPlayerTableEntry(Player, storeName)
	if not entry then
		return nil
	end

	if entry[dataKey] == nil then
		warn(`Key {dataKey} is not a valid key for the entry`)
		return nil
	end

	return entry[dataKey]
end

--- Sets a key within a table-backed store entry.
--- @param Player ValidPlayer a player id or object
--- @param storeName ValidStores the store to update
--- @param dataKey string the key to update
--- @param newDataValue ValidDatastoreValue the value to store
--- @return boolean success whether it was able to be done
local function setPlayerTableEntryData(
	Player: ValidPlayer,
	storeName: ValidStores,
	dataKey: string,
	newDataValue: ValidDatastoreValue
): boolean
	if storeIsServed(storeName) then
		warn(`Store {storeName} is served and cannot use table-edit helpers`)
		return false
	end

	return updateNewestEntryData(Player, storeName, dataKey, newDataValue)
end

--- Increments a number inside a table-backed store entry.
--- @param Player ValidPlayer a player id or object
--- @param storeName ValidStores the store to update
--- @param dataKey string the key to increment
--- @param incrementAmount number the amount to add
--- @return number amount the new amount
local function incrementPlayerTableEntryData(
	Player: ValidPlayer,
	storeName: ValidStores,
	dataKey: string,
	incrementAmount: number
): number
	if storeIsServed(storeName) then
		warn(`Store {storeName} is served and cannot use table-edit helpers`)
		return 0
	end

	return incrementNewestEntry(Player, storeName, dataKey, incrementAmount)
end

--[[----------------------------------------------------------------------------------
	INVENTORY FUNCTIONS
	High-level helpers for owned items, loadouts, and active loadout.
]]
----------------------------------------------------------------------------------

export type PlayerLoadout = {
	[number]: string,
}

export type PlayerLoadouts = {
	[string]: PlayerLoadout,
}

export type LoadoutMutationResult = {
	Success: boolean,
	Reason: string?,
	Loadouts: PlayerLoadouts?,
	ActiveLoadout: string?,
}

export type PlayerInventory = {
	_version: string,
	_served: boolean,
	OwnedItems: { string },
	Loadouts: PlayerLoadouts,
	ActiveLoadout: string,
}

local function deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end

	local copied = {}
	for key, innerValue in pairs(value) do
		copied[key] = deepCopy(innerValue)
	end

	return copied
end

local function getDefaultInventoryTemplate(): PlayerInventory
	local scheme = Schema.getSchemaForStore("Inventory")
	return deepCopy(scheme) :: PlayerInventory
end

local MAX_LOADOUT_NAME_LENGTH = 32
local DEFAULT_MAX_LOADOUTS = 25

local function trimString(value: string): string
	return string.gsub(value, "^%s*(.-)%s*$", "%1")
end

local function isValidLoadoutName(loadoutName: string): (boolean, string?)
	local trimmed = trimString(loadoutName)
	if trimmed == "" then
		return false, "Loadout name cannot be empty"
	end

	if string.len(trimmed) > MAX_LOADOUT_NAME_LENGTH then
		return false, `Loadout name cannot exceed {MAX_LOADOUT_NAME_LENGTH} characters`
	end

	if not string.match(trimmed, "^[%w _%-]+$") then
		return false, "Loadout name contains unsupported characters"
	end

	return true, nil
end

local function countLoadouts(loadouts: PlayerLoadouts): number
	local count = 0
	for _ in pairs(loadouts) do
		count += 1
	end
	return count
end

local function normalizeLoadoutName(loadoutName: string): string
	return trimString(loadoutName)
end

local function validateLoadoutPayload(loadoutData: PlayerLoadout): (boolean, string?)
	if type(loadoutData) ~= "table" then
		return false, "Loadout payload must be a table"
	end

	for key, value in pairs(loadoutData) do
		if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then
			return false, "Loadout keys must be positive integer slot indexes"
		end

		if type(value) ~= "string" then
			return false, "Loadout item names must be strings"
		end
	end

	return true, nil
end

local getPlayerActiveLoadout: (Player: ValidPlayer) -> string?
local setPlayerActiveLoadout: (Player: ValidPlayer, loadoutName: string) -> boolean

local function resetPlayerLoadoutsToDefault(Player: ValidPlayer): boolean
	local inventoryEntry = getNewestEntry(Player, "Inventory")
	if type(inventoryEntry) ~= "table" then
		warn("Could not reset inventory loadouts - entry is malformed")
		return false
	end

	local defaults = getDefaultInventoryTemplate()
	inventoryEntry._version = defaults._version
	inventoryEntry.Loadouts = deepCopy(defaults.Loadouts)
	inventoryEntry.ActiveLoadout = defaults.ActiveLoadout

	return setPlayerEntry(Player, "Inventory", inventoryEntry)
end

local function ensureInventoryLoadoutVersion(Player: ValidPlayer): boolean
	local inventoryEntry = getNewestEntry(Player, "Inventory")
	if type(inventoryEntry) ~= "table" then
		warn("Inventory entry is malformed", type(inventoryEntry))
		return false
	end

	local defaults = getDefaultInventoryTemplate()
	if inventoryEntry._version ~= defaults._version then
		debugWarn("Inventory version mismatch detected, resetting loadouts to defaults")
		return resetPlayerLoadoutsToDefault(Player)
	end

	if type(inventoryEntry.Loadouts) ~= "table" or type(inventoryEntry.ActiveLoadout) ~= "string" then
		debugWarn("Inventory loadout structure is malformed, resetting loadouts to defaults")
		return resetPlayerLoadoutsToDefault(Player)
	end

	return true
end

--- Returns the full inventory entry for a player.
--- @param Player ValidPlayer player id or object
--- @return PlayerInventory? inventory the player's inventory entry
local function getAllPlayerInventory(Player: ValidPlayer): PlayerInventory?
	if not ensureInventoryLoadoutVersion(Player) then
		return nil
	end

	return getNewestEntry(Player, "Inventory") :: PlayerInventory?
end

--- Returns all owned item ids for a player.
--- @param Player ValidPlayer player id or object
--- @return {string} ownedItems list of owned item ids
local function getPlayerOwnedItems(Player: ValidPlayer): { string }
	local inventory = getAllPlayerInventory(Player)
	if not inventory or type(inventory.OwnedItems) ~= "table" then
		return {}
	end

	return inventory.OwnedItems
end

--- Returns true if a player owns a specific item id.
--- @param Player ValidPlayer player id or object
--- @param itemId string the item id to check
--- @return boolean owns whether the item is owned
local function playerOwnsItem(Player: ValidPlayer, itemId: string): boolean
	if itemId == "" then
		return false
	end

	local ownedItems = getPlayerOwnedItems(Player)
	return table.find(ownedItems, itemId) ~= nil
end

--- Adds an item id to a player's owned items list.
--- @param Player ValidPlayer player id or object
--- @param itemId string the item id to add
--- @return boolean success whether the operation succeeded
local function addPlayerOwnedItem(Player: ValidPlayer, itemId: string): boolean
	if itemId == "" then
		warn("Cannot add empty itemId to owned items")
		return false
	end

	if not ensureInventoryLoadoutVersion(Player) then
		return false
	end

	local ownedItems = getPlayerOwnedItems(Player)
	if table.find(ownedItems, itemId) then
		return true
	end

	table.insert(ownedItems, itemId)
	return setPlayerTableEntryData(Player, "Inventory", "OwnedItems", ownedItems)
end

--- Removes an item id from a player's owned items list.
--- @param Player ValidPlayer player id or object
--- @param itemId string the item id to remove
--- @return boolean success whether the operation succeeded
local function removePlayerOwnedItem(Player: ValidPlayer, itemId: string): boolean
	if itemId == "" then
		warn("Cannot remove empty itemId from owned items")
		return false
	end

	if not ensureInventoryLoadoutVersion(Player) then
		return false
	end

	local ownedItems = getPlayerOwnedItems(Player)
	local itemIndex = table.find(ownedItems, itemId)
	if not itemIndex then
		return true
	end

	table.remove(ownedItems, itemIndex)
	return setPlayerTableEntryData(Player, "Inventory", "OwnedItems", ownedItems)
end

--- Returns the full loadouts table.
--- @param Player ValidPlayer player id or object
--- @return PlayerLoadouts? loadouts the player's loadout map
local function getPlayerLoadouts(Player: ValidPlayer): PlayerLoadouts?
	local inventory = getAllPlayerInventory(Player)
	if not inventory then
		return nil
	end

	return inventory.Loadouts
end

local function getPlayerLoadoutsResult(Player: ValidPlayer): LoadoutMutationResult
	local loadouts = getPlayerLoadouts(Player)
	if not loadouts then
		return {
			Success = false,
			Reason = "Could not retrieve player loadouts",
			Loadouts = nil,
			ActiveLoadout = nil,
		}
	end

	return {
		Success = true,
		Reason = nil,
		Loadouts = loadouts,
		ActiveLoadout = getPlayerActiveLoadout(Player),
	}
end

--- Returns one named loadout.
--- @param Player ValidPlayer player id or object
--- @param loadoutName string the loadout name
--- @return PlayerLoadout? loadout the requested loadout
local function getPlayerLoadout(Player: ValidPlayer, loadoutName: string): PlayerLoadout?
	if loadoutName == "" then
		return nil
	end

	local loadouts = getPlayerLoadouts(Player)
	if not loadouts then
		return nil
	end

	return loadouts[loadoutName]
end

--- Sets or replaces a named loadout.
--- @param Player ValidPlayer player id or object
--- @param loadoutName string the loadout name
--- @param loadoutData PlayerLoadout the full loadout payload
--- @return boolean success whether the operation succeeded
local function setPlayerLoadout(Player: ValidPlayer, loadoutName: string, loadoutData: PlayerLoadout | nil): boolean
	if type(loadoutName) ~= "string" then
		warn("Cannot set loadout with non-string name")
		return false
	end

	local normalizedName = normalizeLoadoutName(loadoutName)
	local nameIsValid, nameError = isValidLoadoutName(normalizedName)
	if not nameIsValid then
		warn(nameError)
		return false
	end

	if loadoutData ~= nil then
		local payloadIsValid, payloadError = validateLoadoutPayload(loadoutData)
		if not payloadIsValid then
			warn(payloadError)
			return false
		end
	end

	if not ensureInventoryLoadoutVersion(Player) then
		return false
	end

	local userId = getSafeUserId(Player)
	local store = Core.getStore("Inventory")
	return store:SetNestedEntry(userId, { "Loadouts", normalizedName }, loadoutData)
end

local function upsertPlayerLoadout(
	Player: ValidPlayer,
	loadoutName: string,
	loadoutData: PlayerLoadout,
	maxLoadouts: number?
): LoadoutMutationResult
	if type(loadoutName) ~= "string" then
		return { Success = false, Reason = "Loadout name must be a string" }
	end

	local normalizedName = normalizeLoadoutName(loadoutName)
	local nameIsValid, nameError = isValidLoadoutName(normalizedName)
	if not nameIsValid then
		return { Success = false, Reason = nameError }
	end

	local payloadIsValid, payloadError = validateLoadoutPayload(loadoutData)
	if not payloadIsValid then
		return { Success = false, Reason = payloadError }
	end

	if not ensureInventoryLoadoutVersion(Player) then
		return { Success = false, Reason = "Inventory entry failed validation" }
	end

	local loadouts = getPlayerLoadouts(Player)
	if not loadouts then
		return { Success = false, Reason = "Could not retrieve player loadouts" }
	end

	local maxAllowedLoadouts = math.max(1, math.floor(maxLoadouts or DEFAULT_MAX_LOADOUTS))
	local loadoutExists = loadouts[normalizedName] ~= nil
	if not loadoutExists and countLoadouts(loadouts) >= maxAllowedLoadouts then
		return {
			Success = false,
			Reason = `Loadout limit reached ({maxAllowedLoadouts})`,
			Loadouts = loadouts,
			ActiveLoadout = getPlayerActiveLoadout(Player),
		}
	end

	local success = setPlayerLoadout(Player, normalizedName, loadoutData)
	if not success then
		return {
			Success = false,
			Reason = "Failed to save loadout",
			Loadouts = getPlayerLoadouts(Player),
			ActiveLoadout = getPlayerActiveLoadout(Player),
		}
	end

	local updatedLoadouts = getPlayerLoadouts(Player)
	return {
		Success = true,
		Reason = nil,
		Loadouts = updatedLoadouts,
		ActiveLoadout = getPlayerActiveLoadout(Player),
	}
end

local function removePlayerLoadout(Player: ValidPlayer, loadoutName: string): LoadoutMutationResult
	if type(loadoutName) ~= "string" then
		return { Success = false, Reason = "Loadout name must be a string" }
	end

	local normalizedName = normalizeLoadoutName(loadoutName)
	local nameIsValid, nameError = isValidLoadoutName(normalizedName)
	if not nameIsValid then
		return { Success = false, Reason = nameError }
	end

	if not ensureInventoryLoadoutVersion(Player) then
		return { Success = false, Reason = "Inventory entry failed validation" }
	end

	local loadouts = getPlayerLoadouts(Player)
	if not loadouts then
		return { Success = false, Reason = "Could not retrieve player loadouts" }
	end

	if not loadouts[normalizedName] then
		return {
			Success = false,
			Reason = "Loadout does not exist",
			Loadouts = loadouts,
			ActiveLoadout = getPlayerActiveLoadout(Player),
		}
	end

	if not setPlayerLoadout(Player, normalizedName, nil) then
		return {
			Success = false,
			Reason = "Failed to remove loadout",
			Loadouts = getPlayerLoadouts(Player),
			ActiveLoadout = getPlayerActiveLoadout(Player),
		}
	end

	local activeLoadout = getPlayerActiveLoadout(Player)
	local updatedLoadouts = getPlayerLoadouts(Player) or {}
	if activeLoadout == normalizedName then
		local fallbackLoadout: string? = nil
		for existingName in pairs(updatedLoadouts) do
			fallbackLoadout = existingName
			break
		end

		if fallbackLoadout then
			setPlayerActiveLoadout(Player, fallbackLoadout)
		else
			setPlayerTableEntryData(Player, "Inventory", "ActiveLoadout", "")
		end
	end

	return {
		Success = true,
		Reason = nil,
		Loadouts = getPlayerLoadouts(Player),
		ActiveLoadout = getPlayerActiveLoadout(Player),
	}
end

--- Retrieves a nested entry inside a named loadout.
--- @param Player ValidPlayer player id or object
--- @param loadoutName string the loadout name
--- @param entryPath {ValidDatastoreKey} nested path inside the loadout
--- @return ValidDatastoreValue? value the requested value
local function getPlayerLoadoutEntry(
	Player: ValidPlayer,
	loadoutName: string,
	entryPath: { ValidDatastoreKey }
): ValidDatastoreValue?
	if loadoutName == "" or #entryPath == 0 then
		return nil
	end

	if not ensureInventoryLoadoutVersion(Player) then
		return nil
	end

	local userId = getSafeUserId(Player)
	local store = Core.getStore("Inventory")
	local fullPath = { "Loadouts", loadoutName }
	for _, pathPart in ipairs(entryPath) do
		table.insert(fullPath, pathPart)
	end

	return store:GetNestedEntry(userId, fullPath)
end

--- Sets a nested entry inside a named loadout.
--- @param Player ValidPlayer player id or object
--- @param loadoutName string the loadout name
--- @param entryPath {ValidDatastoreKey} nested path inside the loadout
--- @param newValue ValidDatastoreValue value to write
--- @return boolean success whether the operation succeeded
local function setPlayerLoadoutEntry(
	Player: ValidPlayer,
	loadoutName: string,
	entryPath: { ValidDatastoreKey },
	newValue: ValidDatastoreValue | nil
): boolean
	if loadoutName == "" or #entryPath == 0 then
		warn("Cannot set loadout entry with empty name or path")
		return false
	end

	if not ensureInventoryLoadoutVersion(Player) then
		return false
	end

	local userId = getSafeUserId(Player)
	local store = Core.getStore("Inventory")
	local fullPath = { "Loadouts", loadoutName }
	for _, pathPart in ipairs(entryPath) do
		table.insert(fullPath, pathPart)
	end

	return store:SetNestedEntry(userId, fullPath, newValue)
end

--- Returns the active loadout name.
--- @param Player ValidPlayer player id or object
--- @return string? activeLoadout current active loadout name
getPlayerActiveLoadout = function(Player: ValidPlayer): string?
	if not ensureInventoryLoadoutVersion(Player) then
		return nil
	end

	local activeLoadout = getNewestEntryData(Player, "Inventory", "ActiveLoadout")
	if type(activeLoadout) ~= "string" then
		return nil
	end

	return activeLoadout
end

--- Sets the active loadout name.
--- @param Player ValidPlayer player id or object
--- @param loadoutName string the loadout name to activate
--- @return boolean success whether the operation succeeded
setPlayerActiveLoadout = function(Player: ValidPlayer, loadoutName: string): boolean
	if loadoutName == "" then
		warn("Cannot set empty active loadout")
		return false
	end

	if not ensureInventoryLoadoutVersion(Player) then
		return false
	end

	if not getPlayerLoadout(Player, loadoutName) then
		warn(`Loadout '{loadoutName}' does not exist`)
		return false
	end

	return setPlayerTableEntryData(Player, "Inventory", "ActiveLoadout", loadoutName)
end

--[[----------------------------------------------------------------------------------

	DATASTORE
	Information that is not updated frequently and can be safely read from datastores
	
]]
----------------------------------------------------------------------------------

--[[----------------------------------------------------------------------------------
	GENERAL STORE
	Attempt to get info from SOME store
]]
----------------------------------------------------------------------------------

Module.getStore = Core.getStore
Module.getStoreEntry = Core.getStoreEntry
Module.getAllFlatStores = Core.getAllFlatStores
Module.getAllOrderedStores = Core.getAllOrderedStores
Module.updateStoreEntry = Core.updateStoreEntry
Module.removeStoreEntry = Core.removeStoreEntry

--[[----------------------------------------------------------------------------------
	PLAYER INFO FUNCTIONS
	This involves stats & such
]]
----------------------------------------------------------------------------------

--- NOTE: Keep this updated with PlayerInfo.lua
export type PlayerInfo = {
	_version: string,
	Kills: number,
	Deaths: number,
	Level: number,
	Experience: number,
	Completion: number,
	Credits: number,
	Rank: string,
}

export type ValidPlayerInfoKeys =
	"_version"
	| "Kills"
	| "Deaths"
	| "Level"
	| "Experience"
	| "Completion"
	| "Rank"
	| "Credits"

--- Gets all the info for a player
--- @param Player ValidPlayer player object or userId
--- @return PlayerInfo list of player info
local function getAllPlayerInfo(Player: ValidPlayer): PlayerInfo
	return getNewestEntry(Player, "PlayerInfo")
end

--- Returns specific player info
--- @param Player ValidPlayer player object or userid
--- @param infoKey ValidPlayerInfoKey a info key
--- @return number | string | nil info if it exists
local function getPlayerInfo(Player: ValidPlayer, infoKey: ValidPlayerInfoKeys): number | string | nil
	return getNewestEntryData(Player, "PlayerInfo", infoKey)
end

--- Returns a player's rank
--- @param Player ValidPlayer player object or userid
--- @return PlayerRank rank of the player
local function getPlayerRank(Player: ValidPlayer): PlayerRank
	return getNewestEntryData(Player, "PlayerInfo", "Rank")
end

--- Updates a player's current rank
--- @param Player ValidPlayer player object or userid
--- @param newRank PlayerRank the rank of the player
--- @return success boolean whether it succeded
local function setPlayerRank(Player: ValidPlayer, newRank: PlayerRank): boolean
	return updateNewestEntryData(Player, "PlayerInfo", "Rank", newRank)
end

--- Attempts to update a player's info
--- @param Player ValidPlayer player object or userid
--- @param infoKey ValidPlayerInfoKey a info key
--- @param newValue number | boolean | string new value for the info
--- @return success boolean whether it succeded
local function setPlayerInfo(Player: ValidPlayer, infoKey: ValidPlayerInfoKeys, newValue): boolean
	if infoKey == "Kills" then
		Module.setPlayerKillCount(Player, newValue)
	end
	return updateNewestEntryData(Player, "PlayerInfo", infoKey, newValue)
end

local function incrementPlayerInfo(Player: ValidPlayer, infoKey: ValidPlayerInfoKeys, incrementNumber: number): number
	if infoKey == "Kills" then
		Module.incrementKillCount(Player, incrementNumber)
	end
	return incrementNewestEntry(Player, "PlayerInfo", infoKey, incrementNumber)
end

--[[----------------------------------------------------------------------------------
	PLAYER PREFERENCE FUNCTIONS
	This involves performance/graphical settings & such
]]
----------------------------------------------------------------------------------

--- NOTE: Keep this updated with Preferences.lua
export type PlayerPreferences = {
	_version: string,
	LightingEffects: boolean,
	CameraSway: boolean,
	Materials: boolean,
	DoomMusic: boolean,
	DamageNumbers: boolean,
	HealthBars: boolean,
}

export type ValidPlayerPreferenceKeys =
	"_version"
	| "LightingEffects"
	| "CameraSway"
	| "Materials"
	| "DoomMusic"
	| "DamageNumbers"
	| "HealthBars"

--- Retrieves a list of all player preferences
--- @param Player ValidPlayer a player object or userid
--- @return PlayerPreferences list of player preferences
local function getAllPlayerPreferences(Player: ValidPlayer): PlayerPreferences
	return getNewestEntry(Player, "Preferences")
end

--- Returns a specific player preference
--- @param Player ValidPlayer a player object or userid
--- @param prefKey ValidPlayerPreferenceKeys a preference key
--- @return boolean | nil the preference if it exists
local function getPlayerPreference(Player: ValidPlayer, prefKey: ValidPlayerPreferenceKeys): boolean
	return getNewestEntryData(Player, "Preferences", prefKey)
end

--- Attempts to set a player's preference
--- @param Player ValidPlayer a player object or userid
--- @param prefKey ValidPlayerPreferenceKeys a preference key
--- @param newPref boolean the new preference value
--- @return success boolean whether ir was changed
local function setPlayerPreference(Player: ValidPlayer, prefKey: ValidPlayerPreferenceKeys, newPref: boolean): boolean
	return updateNewestEntryData(Player, "Preferences", prefKey, newPref)
end

--[[----------------------------------------------------------------------------------
	PLAYER FLAG FUNCTIONS
	This involves certain quirks to players (played before, etc)
]]
----------------------------------------------------------------------------------

--- NOTE: Keep this updated with Flags.lua
export type PlayerFlags = {
	_version: string,
	Played: boolean,
	OldDataMigrated: boolean,
	IsVeteran: boolean,
}

export type ValidPlayerFlagKeys = "_version" | "Played" | "OldDataMigrated" | "IsVeteran"

--- Retrieves a list of all player flags
--- @param Player ValidPlayer a player object or userid
--- @return PlayerFlags list of player flags
local function getAllPlayerFlags(Player: ValidPlayer): PlayerFlags
	return getNewestEntry(Player, "Flags")
end

--- Returns a specific player flag
--- @param Player ValidPlayer a player object or userid
--- @param flagKey ValidPlayerFlagKeys a flag key
--- @return boolean | nil the flag if it exists
local function getPlayerFlag(Player: ValidPlayer, flagKey: ValidPlayerFlagKeys): boolean
	return getNewestEntryData(Player, "Flags", flagKey)
end

--- Attempts to set a player's flag
--- @param Player ValidPlayer a player object or userid
--- @param flagKey ValidPlayerFlagKeys a flag key
--- @param newFlagValue boolean the new flag value
--- @return success whether it was changed
local function setPlayerFlag(Player: ValidPlayer, flagKey: ValidPlayerFlagKeys, newFlagValue: boolean): boolean
	return updateNewestEntryData(Player, "Flags", flagKey, newFlagValue)
end

--[[----------------------------------------------------------------------------------
	ORDERED DATA FUNCTIONS
	This involves specific numeral values to player data, such as leaderboard data
]]
----------------------------------------------------------------------------------

--- Returns the amount of kills a player has stored
--- @param Player ValidPlayer a player object or userid
local function getPlayerKillCount(Player: ValidPlayer): number
	return getNewestEntry(Player, "KillCount")
end

--- Changes the amount of kills a player has
--- @param Player ValidPlayer a player object or userid
--- @param newAmount number the new amount of kills
--- @return success whether it was able to be done
local function setPlayerKillCount(Player: ValidPlayer, newAmount: number): boolean
	return updateNewestOrderedEntry(Player, "KillCount", newAmount)
		and updateNewestEntryData(Player, "PlayerInfo", "Kills", newAmount)
end

--- Increments the kill count by a certain number, or 1. Returns the new amount
--- @param Player ValidPlayer a player object or userid
--- @param increment number? the number to increment by (defaults to 1)
--- @return amount the new amount, 0 if failed
local function incrementKillCount(Player: ValidPlayer, increment: number?): number
	local amount = increment or 1
	incrementNewestEntry(Player, "PlayerInfo", "Kills", amount)
	return incrementNewestOrderedEntry(Player, "KillCount", amount)
end

--[[----------------------------------------------------------------------------------

	Function Mapping

]]
----------------------------------------------------------------------------------

Module.getAllPlayerInfo = getAllPlayerInfo
Module.getPlayerInfo = getPlayerInfo
Module.setPlayerInfo = setPlayerInfo
Module.setPlayerRank = setPlayerRank
Module.getPlayerRank = getPlayerRank
Module.incrementPlayerInfo = incrementPlayerInfo

Module.getPlayerTableEntry = getPlayerTableEntry
Module.setPlayerTableEntry = setPlayerTableEntry
Module.getPlayerTableEntryData = getPlayerTableEntryData
Module.setPlayerTableEntryData = setPlayerTableEntryData
Module.incrementPlayerTableEntryData = incrementPlayerTableEntryData

Module.getAllPlayerInventory = getAllPlayerInventory
Module.getPlayerOwnedItems = getPlayerOwnedItems
Module.playerOwnsItem = playerOwnsItem
Module.addPlayerOwnedItem = addPlayerOwnedItem
Module.removePlayerOwnedItem = removePlayerOwnedItem
Module.getPlayerLoadouts = getPlayerLoadouts
Module.getPlayerLoadoutsResult = getPlayerLoadoutsResult
Module.getPlayerLoadout = getPlayerLoadout
Module.setPlayerLoadout = setPlayerLoadout
Module.upsertPlayerLoadout = upsertPlayerLoadout
Module.removePlayerLoadout = removePlayerLoadout
Module.getPlayerLoadoutEntry = getPlayerLoadoutEntry
Module.setPlayerLoadoutEntry = setPlayerLoadoutEntry
Module.getPlayerActiveLoadout = getPlayerActiveLoadout
Module.setPlayerActiveLoadout = setPlayerActiveLoadout
Module.resetPlayerLoadoutsToDefault = resetPlayerLoadoutsToDefault

Module.getAllPlayerPreferences = getAllPlayerPreferences
Module.getPlayerPreference = getPlayerPreference
Module.setPlayerPreference = setPlayerPreference

Module.getAllPlayerFlags = getAllPlayerFlags
Module.getPlayerFlag = getPlayerFlag
Module.setPlayerFlag = setPlayerFlag

Module.getPlayerKillCount = getPlayerKillCount
Module.setPlayerKillCount = setPlayerKillCount
Module.incrementKillCount = incrementKillCount

--[[----------------------------------------------------------------------------------
	INVOKES
]]
----------------------------------------------------------------------------------

-- Utility for safe returns
local function safeInvoke(handler: () -> any)
	local success, result = pcall(handler)
	if not success then
		warn("ServerInvoke Error:", result)
		return nil
	end
	return result
end

local function isValidKey(infoKey, storeName: ValidStores)
	local scheme = Schema.getSchemaForStore(storeName)
	return scheme[infoKey] ~= nil
end

-- Check if a player can access another's data (you can expand this logic)
local function canAccess(Player: Player, target: Player?): boolean
	if not target or not target:IsA("Player") then
		return true
	end
	return (not target or target == Player)
end

DatastoreRep.getAllPlayerInfo.OnServerInvoke = function(Player, otherPlayer)
	return safeInvoke(function()
		if not canAccess(Player, otherPlayer) then
			return nil
		end
		return getAllPlayerInfo(otherPlayer or Player)
	end)
end

DatastoreRep.getPlayerInfo.OnServerInvoke = function(Player, otherPlayer, infoKey)
	return safeInvoke(function()
		if not canAccess(Player, otherPlayer) then
			return nil
		end

		if not isValidKey(infoKey, "PlayerInfo") then
			warn(`[DataAPI] Invalid key received from {Player.Name}: {infoKey}`)
			return nil
		end
		return getPlayerInfo(otherPlayer or Player, infoKey)
	end)
end

DatastoreRep.getPlayerInventory.OnServerInvoke = function(Player, otherPlayer)
	return safeInvoke(function()
		if not canAccess(Player, otherPlayer) then
			return nil
		end
		return getAllPlayerInventory(otherPlayer or Player)
	end)
end

DatastoreRep.getPlayerPreference.OnServerInvoke = function(Player, otherPlayer, prefName)
	return safeInvoke(function()
		if not canAccess(Player, otherPlayer) then
			return nil
		end
		if not isValidKey(prefName, "Preferences") then
			return nil
		end
		return getPlayerPreference(otherPlayer or Player, prefName)
	end)
end

DatastoreRep.getAllPlayerFlags.OnServerInvoke = function(Player, otherPlayer)
	return safeInvoke(function()
		if not canAccess(Player, otherPlayer) then
			return nil
		end
		return getAllPlayerFlags(otherPlayer or Player)
	end)
end

DatastoreRep.getPlayerFlag.OnServerInvoke = function(Player, otherPlayer, flagName)
	return safeInvoke(function()
		if not canAccess(Player, otherPlayer) then
			return nil
		end
		if not isValidKey(flagName, "Flags") then
			return nil
		end
		return getPlayerFlag(otherPlayer or Player, flagName)
	end)
end

DatastoreRep.getPlayerKillCount.OnServerInvoke = function(Player, otherPlayer)
	return safeInvoke(function()
		if not canAccess(Player, otherPlayer) then
			return nil
		end
		return getPlayerKillCount(otherPlayer or Player)
	end)
end

DatastoreRep.setPlayerPreference.OnServerInvoke = function(Player, prefName, prefValue)
	return safeInvoke(function()
		if not isValidKey(prefName, "Preferences") or type(prefValue) ~= "boolean" then
			warn(`[DataAPI] Invalid preference from {Player.Name}: {prefName} = {prefValue}`)
			return false
		end
		DatastoreRep.PreferenceUpdated:FireClient(Player, prefName, prefValue)
		return setPlayerPreference(Player, prefName, prefValue)
	end)
end

--[[----------------------------------------------------------------------------------

	END

]]
----------------------------------------------------------------------------------

return Module
