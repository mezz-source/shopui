--[[------------------------------------------------------------------------------------
   	
   DATASTORE DEBUG MODULE
   
   @module Debug
   @author mezz_inc
   @description The logging and debugging module for the datastore system
   
   @within ServerScriptService/DataAPI
]]
------------------------------------------------------------------------------------

local Debug = {}

--[[----------------------------------------------------------------------------------

	Modules

]]
----------------------------------------------------------------------------------

--- Access the Data API folder
local ServerScriptService = game:GetService("ServerScriptService")
local DataAPI = ServerScriptService:WaitForChild("DataAPI")

--- Dependant modules
local Types = require(DataAPI.Types)
local ErrorTypes = require(DataAPI.ErrorTypes)

--[[----------------------------------------------------------------------------------

	Types

]]
----------------------------------------------------------------------------------

export type ErrorType = Types.ErrorType
export type DatastoreError = Types.DatastoreError

--[[----------------------------------------------------------------------------------

	Variables

]]
----------------------------------------------------------------------------------

--- Whether or not the script will print into the output
--- @type boolean whether it will print
local DEBUG_ENABLED: boolean = false

--[[----------------------------------------------------------------------------------

	Utility Functions

]]
----------------------------------------------------------------------------------

--- Concats a list of arguments into a string. Spaces out each argument with one space
--- @return string the concatted string
local function createOutputFromArgs(...): string
	local args = { ... }
	for i = 1, #args do
		args[i] = tostring(args[i])
	end
	return table.concat(args, " ")
end

--[[----------------------------------------------------------------------------------

	Log Functions

]]

--[[----------------------------------------------------------------------------------

	Print Functions

]]
----------------------------------------------------------------------------------

--- Prints out statement(s) to the output
--- @param ... string? a variable number of strings/types to print
local function debugPrint(...)
	if not DEBUG_ENABLED then
		return
	end
	local output = createOutputFromArgs(...)
	print(output)
end

--- Warn a statement to the output
--- @param ... string? a variable number of strings/types to print
local function debugWarn(...)
	if not DEBUG_ENABLED then
		return
	end
	local output = createOutputFromArgs(...)
	warn(output)
end

--- Raise an error to the output.
--- @param ... string? a variable number of strings/types to print
local function debugError(...)
	if not DEBUG_ENABLED then
		return
	end
	local output = createOutputFromArgs(...)
	error(output, math.huge)
end

--- Creates a debug error object out of the provided params
--- @param sourceName string the name of the module raising the error
--- @param errorType ErrorType the type of error that was raised
--- @param ... string? the message text to add to the error
local function debugErrorType(sourceName: string, errorType: ErrorType, ...)
	local message = createOutputFromArgs(...)
	local newError = ErrorTypes.new(errorType, message) :: DatastoreError
	debugError(sourceName, newError)
end

--[[----------------------------------------------------------------------------------

	Function Mapper

]]
----------------------------------------------------------------------------------

Debug.debugPrint = debugPrint
Debug.debugWarn = debugWarn
Debug.debugError = debugError
Debug.debugErrorType = debugErrorType

return Debug
