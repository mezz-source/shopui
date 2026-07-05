--[[------------------------------------------------------------------------------------
   	
   DATASTORE ERROR TYPE MODULE
   
   @module ErrorTypes
   @author mezz_inc
   @description The error-creation types for the Datastore module.
   
   @within ServerScriptService/DataAPI
]]
------------------------------------------------------------------------------------

local ServerScriptService = game:GetService("ServerScriptService")
local DataAPI = ServerScriptService:WaitForChild("DataAPI")

--[[----------------------------------------------------------------------------------

	Modules

]]
----------------------------------------------------------------------------------

local Types = require(DataAPI.Types)

--[[----------------------------------------------------------------------------------

	Types

]]
----------------------------------------------------------------------------------

export type DatastoreError = Types.DatastoreError
export type ErrorType = Types.ErrorType

--[[----------------------------------------------------------------------------------

	Error Instance

]]
----------------------------------------------------------------------------------

local ErrorTypes = {}
ErrorTypes.__index = ErrorTypes

--- Create a new error type-object
--- @param type ErrorType The type of error
--- @param message string The error message
function ErrorTypes.new(type: ErrorType, message: string): DatastoreError
	local self = setmetatable({}, ErrorTypes)
	self.type = type
	self.message = message
	return self :: DatastoreError
end

--- Returns the string-formatted verrsion of the error object
--- @param self DatastoreError The error object
function ErrorTypes:__tostring(): string
	return `{self.type} Error | {self.message}`
end

return ErrorTypes

--[[----------------------------------------------------------------------------------
]]
----------------------------------------------------------------------------------
