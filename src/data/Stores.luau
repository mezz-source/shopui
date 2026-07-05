--[[------------------------------------------------------------------------------------
   	
   STORES MODULES
   
   @module Stores
   @author mezz_inc
   @description Holds all the active datastores for the place
   
   @within ServerScriptService/DataAPI/Core
      
]]
------------------------------------------------------------------------------------

local Module = {}

--- Name of the module
local NAME: string = "Stores"

--- Required services
local DatastoreService = game:GetService("DataStoreService")

--- Access the Data API folder
local ServerScriptService = game:GetService("ServerScriptService")
local DataAPI = ServerScriptService:WaitForChild("DataAPI")

--- The version of the datastore. Change this to... reset everything
local DATASTORE_VERSION = "-0.1v"

Module._meta = {
	name = NAME,
	version = "1.0.0",
	description = "Holds all the game's active datastores",
}

local LOADED: boolean = false
local GAMEMODE_LOADED: boolean = false
local onGamemodeLoadedCallbacks: { () -> () } = {}

--[[----------------------------------------------------------------------------------

	Modules

]]
----------------------------------------------------------------------------------

--- Dependant modules
local Debug = require(DataAPI.Debug)
local Types = require(DataAPI.Types)
local ErrorModule = require(DataAPI.ErrorTypes)
local Schema = require(DataAPI.Schema)

--[[----------------------------------------------------------------------------------

	Types

]]
----------------------------------------------------------------------------------

export type AllowedStoreTypes = Types.AllowedStoreTypes
export type DatastoreType = Types.DataStoreType
export type ValidDatastoreEntryTypes = Types.ValidDatastoreEntryTypes
export type ValidDatastoreKey = Types.ValidDatastoreKey
export type ValidDatastoreValue = Types.ValidDatastoreValue
export type Store = Types.Store
type ErrorType = Types.ErrorType

--[[----------------------------------------------------------------------------------

	Debug
	Mostly wrapper functions for the Debug module

]]
----------------------------------------------------------------------------------

--- The source name of the module for debugging
local SOURCE_NAME: string = `[DataAPI.Core.{NAME}]`

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

--- Creates a debug error object out of the provided params
--- @param errorType ErrorType the type of error that was raised
--- @param ... string? the message text to add to the error
local function debugErrorType(errorType: ErrorType, ...)
	Debug.debugErrorType(SOURCE_NAME, errorType, ...)
end

--[[----------------------------------------------------------------------------------

	Datastore Entry
	If you want to create a new datastore, please update these values

]]
----------------------------------------------------------------------------------

--- Info associated with pre-created datastores (Optional, but highly encouraged)
--- You can find this with
--- @type {DatastoreInfo} datastoreInfo
local DEFAULT_META_INFO = {
	["KillCount"] = "The amount of kills a player has total",
	["PlayerInfo"] = "Basic player stats (kills, deaths)",
	["Preferences"] = "Player settings",
	["Flags"] = "Certain player quirks T/F",
	["Inventory"] = "Owned items, loadouts, and player inventory state",
}

--- Refer to the type module to help developers see what stores are available currently
--- This is optional, but helps the intellisense for exterior scripts
export type ValidStores = Types.ValidStores

--- All the ordered numeral data stores in the game that should created
--- @type {string} storeName
local ORDERED_STORE_NAMES: { string } = {
	"KillCount",
}

--- All the normal/data varied data stores that should be created
--- @type {string} storeName
local FLAT_STORE_NAMES: { string } = {
	"PlayerInfo",
	"Flags",
	"Preferences",
}

--- Cold stores are persisted only through datastore calls and are never mirrored into player folders.
local COLD_STORE_NAMES: { string } = {
	"Inventory",
}

----- IMPORTANT NOTE   IMPORTANT NOTE    IMPORTANT NOTE   IMPORTANT NOTE

----- IF USING FLAT STORE:
----- Once you added one above, please look into DataAPI > Schema and clone a module,
----- then arrange the data how you want it. Thanks!
--- Valid datastore types as a list
--- @type {string} DatastoreType
local DatastoreTypes = { "DataStore", "OrderedDataStore" }

local DATA_STORES: {
	[DatastoreType]: { [string]: Store },
} = {}

--[[----------------------------------------------------------------------------------

	Helpers

]]

---------------------------------------------------------------------------------

--- Checks whether a store name is in any of the expected store name lists.
--- @param storeName string the store name to check
--- @return boolean expected whether it is a known store
local function isExpectedStore(storeName: string): boolean
	for _, name in ipairs(FLAT_STORE_NAMES) do
		if name == storeName then
			return true
		end
	end
	for _, name in ipairs(COLD_STORE_NAMES) do
		if name == storeName then
			return true
		end
	end
	for _, name in ipairs(ORDERED_STORE_NAMES) do
		if name == storeName then
			return true
		end
	end
	return false
end

--- Raw store lookup without yielding. Returns nil if the store does not exist.
--- @param name string the store name
--- @param storeType DatastoreType? optional type hint
--- @return Store? store the store object if found
local function findStore(name: string, storeType: DatastoreType?): Store?
	if storeType then
		local list = DATA_STORES[storeType]
		if list then
			return list[name]
		end
		return nil
	end

	for _, nameList in pairs(DATA_STORES) do
		if nameList[name] ~= nil then
			return nameList[name]
		end
	end
	return nil
end

--[[----------------------------------------------------------------------------------

	Store Information & Creation

]]
----------------------------------------------------------------------------------

--- Returns the meta info for a given store name
--- @param storeName string the name of the store to get info on
--- @return string the meta info for the store
local function getStoreMetaInfo(storeName: ValidStores | string): string
	if DEFAULT_META_INFO[storeName] == nil then
		return "No meta-info available"
	end
	return DEFAULT_META_INFO[storeName]
end

--- Returns the table value stored at a specific key in a datastore entry.
--- @param store Store the store to inspect
--- @param key ValidDatastoreEntryTypes the entry key
--- @param tableKey ValidDatastoreKey the key inside the table value
--- @return ValidDatastoreValue? the stored table value
--- Use this for single-level table values only.
--- For deeper paths, use GetNestedEntry.
--- Returns the store object with the given name and type if it exists. Errors if the store is missing.
--- If the store is a known gamemode-specific store that hasn't loaded yet (waiting on workspace
--- Gamemode attribute), yields until the gamemode stores are available.
--- @param name string the name of the store
--- @param storeType DatastoreType the type of store to get, if available, otherwise manually searches
--- @return Store store the store object if it exists, or errors "StoreMissing"
local function getStore(name: ValidStores | string, storeType: DatastoreType | nil): Store | nil
	--- Try to find it quickly
	local found = findStore(name, storeType)
	if found then
		return found
	end

	--- If the store is expected but pending gamemode loading, yield
	if not GAMEMODE_LOADED and isExpectedStore(name) and Schema.isGamemodeSpecificStore(name) then
		warn(`[DataAPI.Stores] Store "{name}" is pending gamemode attribute - yielding until loaded`)

		while not GAMEMODE_LOADED do
			task.wait(0.5)
		end

		found = findStore(name, storeType)
		if found then
			return found
		end
	end

	--- Still not found - error
	if storeType then
		error(ErrorModule.new("StoreMissing", `Could not find the Store with the name {name}`))
	else
		debugWarn(ErrorModule.new("StoreMissing", `Could not find the Store with the name {name}`))
	end

	return nil
end

--[[----------------------------------------------------------------------------------

	Getting/setting data

]]
----------------------------------------------------------------------------------

--- Returns whether or not "key" exists in data store
--- @param dataStore DataStore the datastore to check
--- @param key ValidDatastoreEntryTypes the key to check for
--- @return boolean exists whether it exists
local function entryExists(store: Store, key: ValidDatastoreEntryTypes): boolean
	local dataStore = store.DataStore :: AllowedStoreTypes
	local success, result = pcall(dataStore.GetAsync, dataStore, key)
	return success and result ~= nil
end

--- Attempts to get an entry in a data store with a key
--- @param store Store the store to get the entry from
--- @param key ValidDatastoreEntryTypes the key to get the value of
--- @return any value the value of the key
local function getEntry(store: Store, key: ValidDatastoreEntryTypes): any | nil
	if not entryExists(store, key) then
		error(ErrorModule.new("KeyMissing", `Key {key} is not a valid entry in {store.name}`))
		return nil
	end

	--- Attempt to get the entry and return it
	local dataStore = store.DataStore :: AllowedStoreTypes
	local success, result = pcall(dataStore.GetAsync, dataStore, key)

	if not success then
		error(ErrorModule.new("GetFailure", `Unable to get entry {key}: {result}`))
		return nil
	end

	return result
end

--- Attempts to update a store's key value to a new one, and returns if it succeded or not
--- @param store Store The store to set the value in
--- @param key ValidDatastoreEntryTypes The key to set the value of
--- @param value any The value to set the key to
--- @return boolean success if the operation was successful
local function setEntry(store: Store, key: ValidDatastoreEntryTypes, value: any): boolean
	local dataStore = store.DataStore :: AllowedStoreTypes

	if value ~= nil then
		--- Attempt to set key to value in data store
		local success, result = pcall(dataStore.SetAsync, dataStore, key, value)
		if not success then
			debugErrorType("UpdateFailure", `Unable to set {key} to {value}: {result}`)
			return false
		end
	else
		--- Attempt to remove
		local success, result = pcall(dataStore.RemoveAsync, dataStore, key)
		if not success then
			debugErrorType("UpdateFailure", `Unable to remove {key}: {result}`)
			return false
		end
	end

	return true
end

--- Removes an entry from a store
--- @param store Store The store to remove the entry from
--- @param key ValidDatastoreEntryTypes The key to remove
--- @return boolean success if the operation was successful
local function removeEntry(store: Store, key: ValidDatastoreEntryTypes): boolean
	return setEntry(store, key, nil)
end

--- Attempts to get a key in a table in a datastore
--- @param store Store The store to get the entry from
--- @param key ValidDatastoreEntryTypes The key in the store to get
--- @param tableKey ValidDatastoreEntryTypes The key in the table to get
--- @return any | nil the value of the table key if it exists
local function getTableEntry(store: Store, key: ValidDatastoreEntryTypes, tableKey: ValidDatastoreKey): any | nil
	local success, result = pcall(function()
		return getEntry(store, key)
	end)

	if not success then
		error(ErrorModule.new("KeyMissing", `Unable to get {key}: {result}`))
		return nil
	end

	-- Make sure result is a table
	if typeof(result) ~= "table" then
		error(ErrorModule.new("GetFailure", `Key {key} does not point to a table!`))
		return nil
	end

	local value = result[tableKey]
	if value == nil then
		error(ErrorModule.new("KeyMissing", `Key {key} does not exist in result table`))
		return nil
	end

	return value
end

--- Attempts to set a table entry in store to a new value
--- @param store Store The store to set the table entry in
--- @param key ValidDatastoreEntryTypes The key in the store to set
--- @param tableKey ValidDatastoreEntryTypes The key in the table to set
--- @param value any The value to set the table key to
--- @return boolean success if the operation was successful
--- Use this only for single-level dictionary entries.
--- For nested paths, use SetNestedEntry so you do not replace the whole root table by mistake.
local function setTableEntry(
	store: Store,
	key: ValidDatastoreEntryTypes,
	tableKey: ValidDatastoreKey,
	value: ValidDatastoreValue
): boolean
	--- Attempt to get the table
	local success, result = pcall(function()
		return getEntry(store, key)
	end)

	if not success then
		error(ErrorModule.new("GetFailure", `Unable to get {key}: {result}`))
		return false
	end

	-- Make sure result is a table
	if typeof(result) ~= "table" then
		debugErrorType("GetFailure", `Key {key} does not point to a table!`)
		return false
	end

	-- The table and update async
	result[tableKey] = value

	success = pcall(function()
		return setEntry(store, key, result)
	end)

	if not success then
		error(ErrorModule.new("UpdateFailure", `Unable to set {key}::{tableKey} to {value}: {result}`))
		return false
	end

	return true
end

--- Gets the parent table and final key for a nested path inside a datastore entry.
--- @param store Store the store to inspect
--- @param key ValidDatastoreEntryTypes the entry key
--- @param keyPath {ValidDatastoreKey} the nested key path to traverse
--- @return table?, ValidDatastoreKey? parentTable, finalKey if traversal succeeds
local function getNestedTableTarget(
	store: Store,
	key: ValidDatastoreEntryTypes,
	keyPath: { ValidDatastoreKey }
): ({ [any]: any }?, ValidDatastoreKey?)
	if #keyPath == 0 then
		error(ErrorModule.new("KeyMissing", `Key path cannot be empty for {store.name}`))
		return nil, nil
	end

	local success, result = pcall(function()
		return getEntry(store, key)
	end)

	if not success then
		error(ErrorModule.new("KeyMissing", `Unable to get {key}: {result}`))
		return nil, nil
	end

	if typeof(result) ~= "table" then
		error(ErrorModule.new("GetFailure", `Key {key} does not point to a table!`))
		return nil, nil
	end

	local currentTable = result
	for index = 1, #keyPath - 1 do
		local pathKey = keyPath[index]
		local nextValue = currentTable[pathKey]
		if type(nextValue) ~= "table" then
			error(ErrorModule.new("KeyMissing", `Path segment {pathKey} is missing or not a table in {store.name}`))
			return nil, nil
		end
		currentTable = nextValue
	end

	return currentTable, keyPath[#keyPath]
end

--- Attempts to get a nested key in a table in a datastore.
--- @param store Store the store to inspect
--- @param key ValidDatastoreEntryTypes the entry key
--- @param keyPath {ValidDatastoreKey} the nested key path to traverse
--- @return ValidDatastoreValue? the nested value if it exists
--- Path order matters. For example: {"Loadouts", "Default", "Guns", 1}.
--- Returns nil if any intermediate table is missing.
local function getNestedEntry(
	store: Store,
	key: ValidDatastoreEntryTypes,
	keyPath: { ValidDatastoreKey }
): ValidDatastoreValue | nil
	local parentTable, finalKey = getNestedTableTarget(store, key, keyPath)
	if not parentTable or not finalKey then
		return nil
	end

	local value = parentTable[finalKey]
	if value == nil then
		error(ErrorModule.new("KeyMissing", `Key path {table.concat(keyPath, ".")} does not exist in {store.name}`))
		return nil
	end

	return value
end

--- Attempts to set a nested key in a table in a datastore.
--- @param store Store the store to inspect
--- @param key ValidDatastoreEntryTypes the entry key
--- @param keyPath {ValidDatastoreKey} the nested key path to traverse
--- @param value ValidDatastoreValue the value to write
--- @return boolean success if the operation succeeded
--- This mutates the nested leaf, then writes the full root table back to the datastore.
--- Use this for edits like Loadouts.DefaultLoadout.Primary.
local function setNestedEntry(
	store: Store,
	key: ValidDatastoreEntryTypes,
	keyPath: { ValidDatastoreKey },
	value: ValidDatastoreValue
): boolean
	local success, rootEntry = pcall(function()
		return getEntry(store, key)
	end)

	if not success then
		error(ErrorModule.new("GetFailure", `Unable to get {key}: {rootEntry}`))
		return false
	end

	if typeof(rootEntry) ~= "table" then
		debugErrorType("GetFailure", `Key {key} does not point to a table!`)
		return false
	end

	local parentTable = rootEntry
	local finalKey = keyPath[#keyPath]
	if #keyPath == 0 then
		error(ErrorModule.new("KeyMissing", `Key path cannot be empty for {store.name}`))
		return false
	end

	for index = 1, #keyPath - 1 do
		local pathKey = keyPath[index]
		local nextValue = parentTable[pathKey]
		if type(nextValue) ~= "table" then
			error(ErrorModule.new("KeyMissing", `Path segment {pathKey} is missing or not a table in {store.name}`))
			return false
		end
		parentTable = nextValue
	end

	if not parentTable or not finalKey then
		return false
	end

	parentTable[finalKey] = value
	return setEntry(store, key, rootEntry)
end

--- Creates a new store object with the parameters if it does not already exist
--- @param name string the name of the store
--- @param storeType DatastoreType the type of store to create
--- @param dataStore DataStore the store object
--- @param datastoreType DatastoreType the type of datastore to create
--- @return Store store the store object
--- Store objects are instance-style wrappers around the actual datastore functions.
--- Use SetEntry for whole-record writes, SetTableEntry/GetTableEntry for one-level dictionaries,
--- and SetNestedEntry/GetNestedEntry for deeper table paths.
local function createStore(name: string, dataStore: AllowedStoreTypes, datastoreType: DatastoreType): Store
	if DATA_STORES[datastoreType][name] == nil then
		local metaInfo = getStoreMetaInfo(name)

		local store: Store = {
			name = name,
			meta = metaInfo,
			DataStore = dataStore,
			__tostring = `{name} Datastore: {metaInfo}`,

			--- Change a key
			--- Overwrites the entire entry at `key`.
			--- Use this when replacing a full record, not when changing one field.
			SetEntry = function(self: Store, key: ValidDatastoreEntryTypes, value: any): boolean
				local success, result = pcall(Module.setEntry, self, key, value)
				if not success then
					debugWarn("EntryFailure", `AddEntry failed for store '{self.name}'`, result)
					return false, "EntryFailure"
				end
				return true, result
			end,

			--- Reads a single-level table entry such as `WeaponsOwned`.
			--- Returns nil when the key is missing or the root entry is not a table.
			GetTableEntry = function(self: Store, key: ValidDatastoreEntryTypes, tableKey: ValidDatastoreKey)
				local success, result = pcall(Module.getTableEntry, self, key, tableKey)
				if not success then
					debugWarn("EntryFailure", `GetTableEntry failed for store '{self.name}'`, result)
					return nil
				end
				return result
			end,

			--- Writes a single-level table entry such as `WeaponsOwned = {...}` or `Hello = false`.
			--- Do not use this for deeper nested paths.
			SetEntryData = function(
				self: Store,
				key: ValidDatastoreEntryTypes,
				dataKey: ValidDatastoreKey,
				value: ValidDatastoreValue
			): boolean
				local success, result = pcall(Module.setTableEntry, self, key, dataKey, value)
				if not success then
					debugWarn("EntryFailure", `SetEntryData failed for store '{self.name}'`, result)
					return false, "EntryFailure"
				end
				return true, result
			end,

			--- Alias for SetEntryData when you want explicit table-entry naming.
			--- Prefer this when you are working with dictionary-like data.
			SetTableEntry = function(
				self: Store,
				key: ValidDatastoreEntryTypes,
				tableKey: ValidDatastoreKey,
				value: ValidDatastoreValue
			): boolean
				local success, result = pcall(Module.setTableEntry, self, key, tableKey, value)
				if not success then
					debugWarn("EntryFailure", `SetTableEntry failed for store '{self.name}'`, result)
					return false, "EntryFailure"
				end
				return true, result
			end,

			--- Reads a nested value by path.
			--- Example path for Inventory: { "Loadouts", "Default", "Guns", 1 }.
			GetNestedEntry = function(self: Store, key: ValidDatastoreEntryTypes, keyPath: { ValidDatastoreKey })
				local success, result = pcall(Module.getNestedEntry, self, key, keyPath)
				if not success then
					debugWarn("EntryFailure", `GetNestedEntry failed for store '{self.name}'`, result)
					return nil
				end
				return result
			end,

			--- Writes a nested value by path.
			--- This is the safe option when you need to modify a deep field without replacing the whole root table.
			SetNestedEntry = function(
				self: Store,
				key: ValidDatastoreEntryTypes,
				keyPath: { ValidDatastoreKey },
				value: ValidDatastoreValue
			): boolean
				local success, result = pcall(Module.setNestedEntry, self, key, keyPath, value)
				if not success then
					debugWarn("EntryFailure", `SetNestedEntry failed for store '{self.name}'`, result)
					return false, "EntryFailure"
				end
				return true, result
			end,

			--- Removes the entire entry at `key`.
			RemoveEntry = function(self: Store, key: ValidDatastoreEntryTypes): boolean
				local success, result = pcall(Module.removeEntry, self, key)
				if not success then
					debugWarn("EntryFailure", `RemoveEntry failed for store '{self.name}'`, result)
					return false, "EntryFailure"
				end
				return true, result
			end,

			--- Reads the full entry at `key`.
			GetEntry = function(self: Store, key: ValidDatastoreEntryTypes): any?
				local success, result = pcall(Module.getEntry, self, key)
				if not success then
					debugWarn("EntryFailure", `GetEntry failed for store '{self.name}'`, result)
					return false, "EntryFailure"
				end
				return true, result
			end,

			--- Checks whether an entry exists at `key`.
			EntryExists = function(self: Store, key: ValidDatastoreEntryTypes): boolean
				local success, result = pcall(Module.entryExists, self, key)
				if not success then
					debugWarn("EntryFailure", `EntryExists failed for store '{self.name}'`, result)
					return false, "EntryFailure"
				end
				return true, result
			end,

			--- Meta info with the store
			GetMetaInfo = function(self: Store): string
				return self.meta
			end,
		}

		DATA_STORES[datastoreType][name] = store
		return store :: Store
	end

	return DATA_STORES[datastoreType][name] :: Store
end

--- Returns a list of all flat store objects that are currently loaded
--- May be empty if attempted too soon after game creation
local function getAllFlatStores(): { Store }
	local stores = {}
	for _, storeName in ipairs(FLAT_STORE_NAMES) do
		local storeObj = findStore(storeName, "DataStore")
		if not storeObj then
			continue
		end
		table.insert(stores, storeObj)
	end
	return stores
end

--- Returns a list of all ordered store objects that are currently loaded
--- May be empty if attempted too soon after game creation
local function getAllOrderedStores(): { Store }
	local stores = {}
	for _, storeName in ipairs(ORDERED_STORE_NAMES) do
		local storeObj = findStore(storeName, "OrderedDataStore")
		if not storeObj then
			continue
		end
		table.insert(stores, storeObj)
	end
	return stores
end

--- Returns a list of all cold stores that are currently loaded.
local function getAllColdStores(): { Store }
	local stores = {}
	for _, storeName in ipairs(COLD_STORE_NAMES) do
		local storeObj = findStore(storeName, "DataStore")
		if not storeObj then
			continue
		end
		table.insert(stores, storeObj)
	end
	return stores
end

--- Returns the game specific store name
local function getGameSpecificName(storeName: string): string
	if Schema.isGamemodeSpecificStore(storeName) then
		local currentGamemode = workspace:GetAttribute("Gamemode")

		if currentGamemode == "Sandbox" then
			currentGamemode = ""
		else
			currentGamemode = `_{currentGamemode}`
		end

		print(`{storeName}{currentGamemode}`)
		return `{storeName}{currentGamemode}`
	end

	print(storeName)
	return storeName
end

--[[----------------------------------------------------------------------------------

	Module Functions
	Unlike mapping, this is required for basic store classes

]]
----------------------------------------------------------------------------------

--- Returns the store object with the given name and type if it exists. Errors if the store is missing
--- @param name string the name of the store
--- @param storeType DatastoreType the type of store to get, if available, otherwise manually searches
--- @return Store store the store object if it exists, or errors "StoreMissing"
function Module.getStore(name: ValidStores | string, storeType: DatastoreType | nil): Store | nil
	return getStore(name, storeType)
end

--- Returns whether or not "key" exists in data store
--- @param dataStore DataStore the datastore to check
--- @param key ValidDatastoreEntryTypes the key to check for
--- @return boolean exists whether it exists
function Module.entryExists(store: Store, key: ValidDatastoreEntryTypes): boolean
	return entryExists(store, key)
end

--- Attempts to get an entry in a data store with a key
--- @param store Store the store to get the entry from
--- @param key ValidDatastoreEntryTypes the key to get the value of
--- @return any value the value of the key
function Module.getEntry(store: Store, key: ValidDatastoreEntryTypes): any | nil
	return getEntry(store, key)
end

--- Attempts to update a store's key value to a new one, and returns if it succeded or not
--- @param store Store The store to set the value in
--- @param key ValidDatastoreEntryTypes The key to set the value of
--- @param value any The value to set the key to
--- @return boolean success if the operation was successful
function Module.setEntry(store: Store, key: ValidDatastoreEntryTypes, value: any): boolean
	return setEntry(store, key, value)
end

--- Removes an entry from a store
--- @param store Store The store to remove the entry from
--- @param key ValidDatastoreEntryTypes The key to remove
--- @return boolean success if the operation was successful
function Module.removeEntry(store: Store, key: ValidDatastoreEntryTypes): boolean
	return removeEntry(store, key)
end

--- Attempts to get a key in a table in a datastore
--- @param store Store The store to get the entry from
--- @param key ValidDatastoreEntryTypes The key in the store to get
--- @param tableKey ValidDatastoreEntryTypes The key in the table to get
--- @return any | nil the value of the table key if it exists
function Module.getTableEntry(store: Store, key: ValidDatastoreEntryTypes, tableKey: ValidDatastoreKey): any | nil
	return getTableEntry(store, key, tableKey)
end

--- Attempts to set a table entry in store to a new value
--- @param store Store The store to set the table entry in
--- @param key ValidDatastoreEntryTypes The key in the store to set
--- @param tableKey ValidDatastoreEntryTypes The key in the table to set
--- @param value any The value to set the table key to
--- @return boolean success if the operation was successful
function Module.setTableEntry(
	store: Store,
	key: ValidDatastoreEntryTypes,
	tableKey: ValidDatastoreKey,
	value: ValidDatastoreValue
): boolean
	return setTableEntry(store, key, tableKey, value)
end

--- Attempts to get a nested key in a table in a datastore.
--- @param store Store the store to inspect
--- @param key ValidDatastoreEntryTypes the entry key
--- @param keyPath {ValidDatastoreKey} the nested key path to traverse
--- @return ValidDatastoreValue? the nested value if it exists
function Module.getNestedEntry(
	store: Store,
	key: ValidDatastoreEntryTypes,
	keyPath: { ValidDatastoreKey }
): ValidDatastoreValue | nil
	return getNestedEntry(store, key, keyPath)
end

--- Attempts to set a nested key in a table in a datastore.
--- @param store Store the store to inspect
--- @param key ValidDatastoreEntryTypes the entry key
--- @param keyPath {ValidDatastoreKey} the nested key path to traverse
--- @param value ValidDatastoreValue the value to write
--- @return boolean success if the operation succeeded
function Module.setNestedEntry(
	store: Store,
	key: ValidDatastoreEntryTypes,
	keyPath: { ValidDatastoreKey },
	value: ValidDatastoreValue
): boolean
	return setNestedEntry(store, key, keyPath, value)
end

Module.getAllFlatStores = getAllFlatStores
Module.getAllOrderedStores = getAllOrderedStores
Module.getAllColdStores = getAllColdStores

--[[----------------------------------------------------------------------------------

	Start & Test Features

]]
----------------------------------------------------------------------------------

--- Creates gamemode-specific DataStore wrappers after the workspace Gamemode attribute
--- has been set. Called automatically by load() when the attribute changes.
local function loadGamemodeStores()
	debugPrint("🟡🟡 Loading gamemode-specific stores 🟡🟡")

	local success, result = pcall(function()
		for _, storeName: string in ipairs(FLAT_STORE_NAMES) do
			if Schema.isGamemodeSpecificStore(storeName) then
				local updatedStoreName = getGameSpecificName(storeName)
				local dataStore: AllowedStoreTypes =
					DatastoreService:GetDataStore(updatedStoreName .. DATASTORE_VERSION)
				local store: Store = createStore(storeName, dataStore, "DataStore")
				debugPrint("Created:", store.__tostring)
			end
		end

		for _, storeName: string in ipairs(COLD_STORE_NAMES) do
			if Schema.isGamemodeSpecificStore(storeName) then
				local updatedStoreName = getGameSpecificName(storeName)
				local dataStore: AllowedStoreTypes =
					DatastoreService:GetDataStore(updatedStoreName .. DATASTORE_VERSION)
				local store: Store = createStore(storeName, dataStore, "DataStore")
				debugPrint("Created:", store.__tostring)
			end
		end

		for _, storeName: string in ipairs(ORDERED_STORE_NAMES) do
			if Schema.isGamemodeSpecificStore(storeName) then
				local updatedStoreName = getGameSpecificName(storeName)
				local dataStore: AllowedStoreTypes =
					DatastoreService:GetOrderedDataStore(updatedStoreName .. DATASTORE_VERSION)
				local store: Store = createStore(storeName, dataStore, "OrderedDataStore")
				debugPrint("Created:", store.__tostring)
			end
		end
	end)

	if not success then
		debugWarn("🔴🔴 Could not create gamemode-specific Datastores! 🔴🔴", result)
		return
	end

	GAMEMODE_LOADED = true
	debugPrint("🟢🟢 Gamemode-specific stores fully loaded 🟢🟢")

	--- Fire callbacks so downstream systems (e.g. Manager) can re-sync existing players
	for _, cb in ipairs(onGamemodeLoadedCallbacks) do
		task.spawn(cb)
	end
end

--- Initalization function
--- Phase 1: loads non-gamemode-specific stores immediately so Preferences are available.
--- Phase 2: registers a listener on workspace:GetAttribute("Gamemode"); when it becomes
--- non-empty the gamemode-specific stores are created.
local function load()
	debugPrint("🟡🟡 Beginning Data API Build 🟡🟡")

	--- Add the valid datastore type keys
	for _, validType: DatastoreType in ipairs(DatastoreTypes) do
		DATA_STORES[validType] = {}
	end

	--- Phase 1: load non-gamemode-specific stores only
	local success, result = pcall(function()
		for _, storeName: string in ipairs(FLAT_STORE_NAMES) do
			if not Schema.isGamemodeSpecificStore(storeName) then
				local updatedStoreName = getGameSpecificName(storeName)
				local dataStore: AllowedStoreTypes =
					DatastoreService:GetDataStore(updatedStoreName .. DATASTORE_VERSION)
				local store: Store = createStore(storeName, dataStore, "DataStore")
				debugPrint("Created:", store.__tostring)
			end
		end

		for _, storeName: string in ipairs(COLD_STORE_NAMES) do
			if not Schema.isGamemodeSpecificStore(storeName) then
				local updatedStoreName = getGameSpecificName(storeName)
				local dataStore: AllowedStoreTypes =
					DatastoreService:GetDataStore(updatedStoreName .. DATASTORE_VERSION)
				local store: Store = createStore(storeName, dataStore, "DataStore")
				debugPrint("Created:", store.__tostring)
			end
		end

		for _, storeName: string in ipairs(ORDERED_STORE_NAMES) do
			if not Schema.isGamemodeSpecificStore(storeName) then
				local updatedStoreName = getGameSpecificName(storeName)
				local dataStore: AllowedStoreTypes =
					DatastoreService:GetOrderedDataStore(updatedStoreName .. DATASTORE_VERSION)
				local store: Store = createStore(storeName, dataStore, "OrderedDataStore")
				debugPrint("Created:", store.__tostring)
			end
		end
	end)

	if not success then
		debugWarn("🔴🔴 Could not create base Datastores! 🔴🔴", result)
		return
	end

	debugPrint("🟢🟢 Base stores loaded — Data API operational 🟢🟢")
	LOADED = true

	--- Phase 2: schedule gamemode-specific stores
	if not GAMEMODE_LOADED then
		local currentGamemode = workspace:GetAttribute("Gamemode")
		if currentGamemode and currentGamemode ~= "" then
			--- Already set, load immediately
			loadGamemodeStores()
		else
			--- Wait for it to be set
			local connection: RBXScriptConnection
			connection = workspace:GetAttributeChangedSignal("Gamemode"):Connect(function()
				local newGamemode = workspace:GetAttribute("Gamemode")
				if newGamemode and newGamemode ~= "" then
					connection:Disconnect()
					task.spawn(loadGamemodeStores)
				end
			end)
		end
	end
end

--- Runs a developer test on the module
local function test() end

--[[----------------------------------------------------------------------------------

	END

]]
----------------------------------------------------------------------------------

Module.loaded = function()
	return LOADED
end

Module.gamemodeLoaded = function()
	return GAMEMODE_LOADED
end

Module.onGamemodeStoresLoaded = function(callback: () -> ())
	table.insert(onGamemodeLoadedCallbacks, callback)
	if GAMEMODE_LOADED then
		task.spawn(callback)
	end
end

--- Calling module.start() will start the module
--- Calling module.test() will test a function of the module
Module.load = load
Module.test = test

return Module
