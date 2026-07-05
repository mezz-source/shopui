--[[------------------------------------------------------------------------------------
   	
   DATASTORE CORE MODULE
   
   @module Core
   @author mezz_inc
   @description Handles the getting, setting, and updating of Datastores
   
   @within ServerScriptService/DataAPI
   
   
   Initialization
   
]]
------------------------------------------------------------------------------------

local Module = {}

--- Name of the module
local NAME: string = "Core"

--- Access the Data API folder
local ServerScriptService = game:GetService("ServerScriptService")
local DataAPI = ServerScriptService:WaitForChild("DataAPI")

Module._meta = {
	name = NAME,
	version = "1.0.0",
	description = "Handles the getting, setting, and updating of Datastores",
}

--[[----------------------------------------------------------------------------------

	Modules

]]
----------------------------------------------------------------------------------

--- Dependant modules
local Debug = require(DataAPI.Debug)
local Types = require(DataAPI.Types)
local Schema = require(DataAPI.Schema)
local Stores = require(DataAPI.Stores)

--[[----------------------------------------------------------------------------------

	Types

]]
----------------------------------------------------------------------------------

export type AllowedStoreTypes = Types.AllowedStoreTypes
export type DatastoreType = Types.DataStoreType
export type Store = Types.Store

export type ValidStores = Stores.ValidStores

type ErrorType = Types.ErrorType

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

------------------------- Module

--[[----------------------------------------------------------------------------------

	Local Functions

]]
----------------------------------------------------------------------------------

local function yieldToLoad()
	--- not debug warn as this is for YOU buddy
	if not Stores.loaded() then
		warn("Attempt to access the Data API too early - yielding until fully loaded")

		while not Stores.loaded() do
			task.wait(0.5)
		end
	end
end

--- Returns the store object if it exists, otherwise returns a fallback one
--- @param storeName string the name of the store to get
--- @return Store the store object
local function getStore(storeName: ValidStores | string): Store
	yieldToLoad()

	local success, result = pcall(function()
		return Stores.getStore(storeName)
	end)

	-- Fallback store
	if not success then
		-- Most likely occurs if you try and do this too fast when the game starts
		if #Stores.getAllFlatStores() + #Stores.getAllOrderedStores() == 0 then
			local total = #Stores.getAllFlatStores() + #Stores.getAllOrderedStores()
			repeat
				total = #Stores.getAllFlatStores() + #Stores.getAllOrderedStores()
				task.wait(3)
			until total ~= 0
		end

		debugWarn("StoreMissing", `Store {storeName} is not a loaded store`)

		return {
			name = storeName,
			meta = "Invalid",
			DataStore = nil,
			__tostring = "Invalid Store",
			SetEntry = function()
				return false
			end,
			GetEntry = function()
				return nil
			end,
			RemoveEntry = function()
				return false
			end,
			EntryExists = function()
				return false
			end,
		} :: Store
	end

	return result
end

--- Returns the store entry of the storename if it exists
--- @param storeName string the name of the store to get the entry of
--- @param key any the key to check
--- @return any? the store entry
local function getStoreEntry(storeName: ValidStores | string, key: any): any | nil
	yieldToLoad()

	local store = getStore(storeName) :: Store

	local success, result = pcall(function()
		return Stores.getEntry(store, key)
	end)

	if success then
		return result
	end
	return nil
end

--- Updates the store entry of the storename
--- @param storeName string the name of the store to get the entry of
--- @param key any the key to set
--- @param value any the value to set
--- @return boolean success if it succeded
local function updateStoreEntry(storeName: ValidStores | string, key: any, value: any): boolean
	yieldToLoad()

	local store = getStore(storeName) :: Store

	local success, _ = pcall(function()
		return Stores.setEntry(store, key, value)
	end)

	return success
end

--- Removes the store entry of the storename
--- @param storeName string the name of the store to get the entry of
--- @param key any the key to remove
--- @return boolean success if it succeded
local function removeStoreEntry(storeName: ValidStores | string, key: any): boolean
	yieldToLoad()

	local store = getStore(storeName) :: Store

	local success, _ = pcall(function()
		return Stores.removeEntry(store, key)
	end)

	return success
end

--- Checks if the store entry of the storename exists
--- @param storeName string the name of the store to get the entry of
--- @param key any the key to check
--- @return boolean success if it exists
local function storeEntryExists(storeName: ValidStores | string, key: any): boolean
	yieldToLoad()

	local store = getStore(storeName) :: Store

	local success, result = pcall(function()
		return Stores.entryExists(store, key)
	end)

	if success then
		return result
	end
	return false
end

--[[----------------------------------------------------------------------------------

	Function Mapping

]]
----------------------------------------------------------------------------------

Module.getStore = getStore
Module.getStoreEntry = getStoreEntry
Module.updateStoreEntry = updateStoreEntry
Module.removeStoreEntry = removeStoreEntry
Module.storeEntryExists = storeEntryExists
Module.getAllFlatStores = Stores.getAllFlatStores
Module.getAllOrderedStores = Stores.getAllOrderedStores
Module.getAllColdStores = Stores.getAllColdStores
Module.getTableEntry = Stores.getTableEntry
Module.setTableEntry = Stores.setTableEntry
Module.getNestedEntry = Stores.getNestedEntry
Module.setNestedEntry = Stores.setNestedEntry

--[[----------------------------------------------------------------------------------

	Start & Test Features

]]
----------------------------------------------------------------------------------

--- Initalization function
local function start()
	Schema.start()
	Stores.load()
	debugPrint("Module is ready")
end

--- Runs a developer test on the module
local function test()
	debugPrint("Getting prefs")
	local coolStore = getStore("Preferences") :: Store

	print(coolStore)

	debugPrint("Getting a value")
	local succes, res = coolStore:set()
	if not succes then
		print("oopsie poopise:", res)
	end
end

--[[----------------------------------------------------------------------------------

	END

]]
----------------------------------------------------------------------------------

Module.isLoaded = function()
	return Stores.loaded()
end

--- Calling module.start() will start the module
--- Calling module.test() will test a function of the module
Module.start = start
Module.test = test

return Module
