--[[------------------------------------------------------------------------------------
   	
   DATASTORE SCHEMA MODULE
   
   @module Scheme
   @author mezz_inc
   @description Handles the layouts of the data stores values
   
   @within ServerScriptService/DataAPI
   
   
   Initialization
   
]]
------------------------------------------------------------------------------------

local Module = {}

--- Name of the module
local NAME: string = "Schema"

--- Access the Data API folder
local ServerScriptService = game:GetService("ServerScriptService")
local DataAPI = ServerScriptService:WaitForChild("DataAPI")

local SchemeLocation = script.Parent.Schemes

Module._meta = {
	name = NAME,
	version = "1.0.0",
	description = "Data-layouts for specific datastores",
}

--[[----------------------------------------------------------------------------------

	Modules

]]
----------------------------------------------------------------------------------

--- Dependant modules
local Debug = require(DataAPI.Debug)
local ErrorModule = require(DataAPI.ErrorTypes)
local Types = require(DataAPI.Types)

--[[----------------------------------------------------------------------------------

	Types

]]
----------------------------------------------------------------------------------

type ErrorType = Types.ErrorType

type ValidStores = Types.ValidStores

type ValidInstanceValues = Types.ValidInstanceValues

type ValidDatastoreEntryTypes = Types.ValidDatastoreEntryTypes

type ValidDatastoreValue = Types.ValidDatastoreValue

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

local validInstanceTypes: { string } = { "StringValue", "BoolValue", "NumberValue" }

--[[----------------------------------------------------------------------------------

	Local Functions

]]
----------------------------------------------------------------------------------

--- Returns whether or not a given scheme exists
--- @param dataStoreName string the name of the store to check
--- @return boolean exists whether it exists
local function schemeExists(dataStoreName: ValidStores | string): boolean
	return SchemeLocation:FindFirstChild(dataStoreName) ~= nil
end

--- Returns the schema for a given store name
--- @param dataStoreName string the name of the store to get the schema of
--- @return table schema the schema of the store
local function getSchemaForStore(dataStoreName: ValidStores | string): { [any]: any }
	local scheme = SchemeLocation:FindFirstChild(dataStoreName) :: Instance?
	if not scheme then
		debugWarn(`No scheme available for "{dataStoreName}" returning empty table!`)
		return {}
	end

	local schemeTable = require(scheme) :: { [any]: any }
	return schemeTable
end

--- Returns whether the store should be mirrored into the player's data folder
--- @param dataStoreName string the name of the store to inspect
--- @return boolean served whether the store is hot-served
local function isServedStore(dataStoreName: ValidStores | string): boolean
	local scheme = getSchemaForStore(dataStoreName)
	if scheme._served == nil then
		return true
	end
	return scheme._served == true
end

--- Creates a list of instance values based on an array of data and returns the list
--- Returns dynamic value instances based on the value of inputTable[x]
--- Assumes the key is a string for the name of the value, is a string, number, or bool value-wise
--- @param inputTable {[string]: any} the table to create the instances from
--- @return {ValidInstanceValues} instanceList the list of instances created
local function tableToInstances(
	inputTable: { [string]: ValidDatastoreValue },
	isServed: boolean?
): { ValidInstanceValues }
	local typeToInstanceType: { [string]: string } = {
		["string"] = "StringValue",
		["number"] = "NumberValue",
		["boolean"] = "BoolValue",
	}

	local instanceList: { ValidInstanceValues } = {}

	for key, value in pairs(inputTable) do
		if key == "_served" then
			continue
		end

		local valueType = type(value) :: string

		if valueType == "table" then
			if isServed then
				error(ErrorModule.new("EntryFailure", "Hot stores only permit simple entries"))
			end
			debugWarn("Unable to create instance value for", key .. ", tables are not supported in the data folder")
			continue
		end

		if typeToInstanceType[valueType] == nil then
			debugWarn("Unable to create instance value for", key .. ", must be a string, number, or bool value")
			continue
		end

		local instanceName = typeToInstanceType[valueType] :: string
		local newInstanceValue = Instance.new(instanceName) :: ValidInstanceValues
		newInstanceValue.Name = key

		local success, _ = pcall(function()
			newInstanceValue.Value = value
		end)

		if not success then
			debugPrint("Value mismatch:", key, " cannot be made value", value)
		end

		table.insert(instanceList, newInstanceValue)
	end

	return instanceList
end

--- Creates a list from instance values based on their name, and current value
--- Returns a key-pair instance of InstanceName = Value
--- Assumes all Instances are either a StringValue, NumberValue, or BoolValue
--- @param instanceList {ValidInstanceValues} the list of instances to create the table from
--- @return {[string]: any} table the table created from the instances
local function instancesToTable(
	instanceList: { ValidInstanceValues | Instance }
): { [string]: ValidDatastoreEntryTypes }
	local newTable = {}
	for _, instance in ipairs(instanceList) do
		local instanceType = instance.ClassName :: ValidInstanceValues
		local instanceName = instance.Name :: string

		if not table.find(validInstanceTypes, instanceType) then
			debugWarn("Attempt to store a non-valid instance type:", instanceType)
			continue
		end

		local value = instance.Value
		newTable[instanceName] = value
	end

	return newTable
end

--- Returns a folder of values based on the input table, and the store name
--- By default has no parent
--- @param storeName string the name of the store to create the folder from
--- @param EntryTable {[string]: any} the table to create the folder from
--- @return Folder folder the folder created from the table
local function constructFolderFromEntryTable(storeName: string, EntryTable: { [string]: ValidDatastoreValue }): Folder
	local newFolder = Instance.new("Folder")
	newFolder.Name = storeName

	--- Create the instances
	local instances = tableToInstances(EntryTable, true) :: { ValidInstanceValues }
	for _, instance in ipairs(instances) do
		instance.Parent = newFolder
	end

	return newFolder :: Folder
end

--[[----------------------------------------------------------------------------------

	Function Mappers

]]
----------------------------------------------------------------------------------

Module.schemeExists = schemeExists
Module.getSchemaForStore = getSchemaForStore
Module.isServedStore = isServedStore
Module.tableToInstances = tableToInstances
Module.instancesToTable = instancesToTable
Module.constructFolderFromEntryTable = constructFolderFromEntryTable

--[[----------------------------------------------------------------------------------

	Start & Test Features

]]
----------------------------------------------------------------------------------

--- Initalization function
local function start() end

--- Runs a developer test on the module
local function test() end

--[[----------------------------------------------------------------------------------

	END

]]
----------------------------------------------------------------------------------

--- Calling module.start() will start the module
--- Calling module.test() will test a function of the module
Module.start = start
Module.test = test

return Module
