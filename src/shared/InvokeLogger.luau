local InvokeLogger = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local LOG_ENABLED = false
local totalInvokeServerCalls = 0
local totalBindableCalls = 0
local invokeServerLog = {}
local bindableLog = {}

local MAX_LOG_SIZE = 500

local function sanitizeArg(arg: any): string
	local t = typeof(arg)
	if t == "string" then
		if #arg > 30 then
			return `"{arg:sub(1, 27)}..."`
		end
		return `"{arg}"`
	end
	if t == "number" or t == "boolean" then
		return tostring(arg)
	end
	if t == "table" then
		return "table"
	end
	return tostring(arg)
end

local function formatArgs(...): string
	local parts = { ... }
	for i, part in ipairs(parts) do
		parts[i] = sanitizeArg(part)
	end
	return table.concat(parts, ", ")
end

function InvokeLogger.invokeServer(remote: RemoteFunction, ...)
	totalInvokeServerCalls += 1

	local argsStr = formatArgs(...)
	local logEntry = `[Invoke #{totalInvokeServerCalls}] {remote.Name}({argsStr})`

	table.insert(invokeServerLog, logEntry)
	if #invokeServerLog > MAX_LOG_SIZE then
		table.remove(invokeServerLog, 1)
	end

	if LOG_ENABLED then
		print(logEntry)
	end

	return remote:InvokeServer(...)
end

function InvokeLogger.invoke(bindable: BindableFunction, ...)
	totalBindableCalls += 1

	local argsStr = formatArgs(...)
	local logEntry = `[Bindable #{totalBindableCalls}] {bindable.Name}({argsStr})`

	table.insert(bindableLog, logEntry)
	if #bindableLog > MAX_LOG_SIZE then
		table.remove(bindableLog, 1)
	end

	if LOG_ENABLED then
		print(logEntry)
	end

	return bindable:Invoke(...)
end

function InvokeLogger.getServerInvokeCount(): number
	return totalInvokeServerCalls
end

function InvokeLogger.getBindableInvokeCount(): number
	return totalBindableCalls
end

function InvokeLogger.getTotalCount(): number
	return totalInvokeServerCalls + totalBindableCalls
end

function InvokeLogger.setEnabled(enabled: boolean)
	LOG_ENABLED = enabled
end

function InvokeLogger.printReport()
	print("========== Invoke Logger Report ==========")
	print(`Client -> Server (InvokeServer): {totalInvokeServerCalls}`)
	print(`Server -> Server (Bindable):     {totalBindableCalls}`)
	print(`Total:                            {InvokeLogger.getTotalCount()}`)
	if totalInvokeServerCalls > 100 then
		warn(
			`High invoke count ({totalInvokeServerCalls} InvokeServer calls) - consider throttling if experiencing lag`
		)
	end
	print("==========================================")
end

function InvokeLogger.getInvokeServerLog(): { string }
	return invokeServerLog
end

function InvokeLogger.getBindableLog(): { string }
	return bindableLog
end

if RunService:IsServer() then
	game:BindToClose(function()
		if totalInvokeServerCalls > 0 or totalBindableCalls > 0 then
			InvokeLogger.printReport()
		end
	end)
end

return InvokeLogger
