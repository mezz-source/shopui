--[[------------------------------------------------------------------------------------
   	
   DATASTORE SCHEMA MODULE
   
   @module Types
   @author mezz_inc
   @description Holds the types used in the datastore module
   
   @within ServerScriptService/DataAPI
]]
------------------------------------------------------------------------------------

local Types = {}

--[[----------------------------------------------------------------------------------

	TYPES

]]
----------------------------------------------------------------------------------

export type DatastoreError = {
	["type"]: ErrorType,
	["message"]: string,
	["__tostring"]: (self: DatastoreError) -> string,
	["new"]: (type: ErrorType, message: string) -> DatastoreError,
}

export type ValidDatastorePrimitive = number | boolean | string

export type ValidDatastoreKey = string | number

export type ValidDatastoreValue =
	ValidDatastorePrimitive
	| { [string]: ValidDatastoreValue }
	| { [number]: ValidDatastoreValue }

export type ErrorType =
	"ServiceUnavailable"
	| "DatastoreMissing"
	| "KeyMissing"
	| "StoreFailure"
	| "GetFailure"
	| "UpdateFailure"
	| "DeleteFailure"
	| "StoreMissing"
	| "EntryFailure"

export type Store = {
	["name"]: string,
	["meta"]: string,
	["DataStore"]: DataStore | OrderedDataStore,
	["__tostring"]: string,
	["SetEntry"]: (self: Store, key: any, value: ValidDatastoreValue) -> boolean,
	["GetEntry"]: (self: Store, key: any) -> ValidDatastoreValue | nil,
	["GetMetaInfo"]: (self: Store) -> string,
	["RemoveEntry"]: (self: Store, key: any) -> boolean,
	["EntryExists"]: (self: Store, key: any) -> boolean,
	["SetEntryData"]: (
		self: Store,
		key: any,
		keyValue: ValidDatastoreKey,
		newValue: ValidDatastoreValue
	) -> boolean,
	["GetTableEntry"]: (self: Store, key: any, tableKey: ValidDatastoreKey) -> ValidDatastoreValue | nil,
	["SetTableEntry"]: (
		self: Store,
		key: any,
		tableKey: ValidDatastoreKey,
		newValue: ValidDatastoreValue
	) -> boolean,
	["GetNestedEntry"]: (self: Store, key: any, keyPath: { ValidDatastoreKey }) -> ValidDatastoreValue | nil,
	["SetNestedEntry"]: (
		self: Store,
		key: any,
		keyPath: { ValidDatastoreKey },
		newValue: ValidDatastoreValue
	) -> boolean,
}

export type ValidPlayer = Player | number

export type AllowedStoreTypes = DataStore | OrderedDataStore | GlobalDataStore

export type DataStoreType = "DataStore" | "OrderedDataStore" | "GlobalDataStore"

export type ValidStores = "KillCount" | "PlayerInfo" | "Preferences" | "Flags" | "Inventory"

export type ValidInstanceValues = NumberValue | BoolValue | StringValue

export type ValidDatastoreEntryTypes = ValidDatastoreValue

export type PlayerRanks = "None" | "Play-Tester" | "Contributor" | "Admin" | "Developer"

--[[----------------------------------------------------------------------------------
]]
----------------------------------------------------------------------------------

return Types
