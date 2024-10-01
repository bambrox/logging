--[[
Copyright 2024 Michael and Simeon Bamford ("Bambros")
Functional Source License, Version 1.1, ALv2 Future License
https://github.com/getsentry/fsl.software/blob/main/FSL-1.1-ALv2.template.md

This module defines functions commonly used across the code base. It has no knowledge of the Roblox API.
]]

-- QUEUE IMPLEMENTATION: https://create.roblox.com/docs/luau/queues

local Queue = {}
Queue.__index = Queue

function Queue.new()
	local self = setmetatable({}, Queue)
	self.first = 0
	self.last = -1
	self.queue = {}
	return self
end

--[[
	Check if the queue is empty
]]
function Queue:isEmpty()
	return self.first > self.last
end

--[[
	Add a value to the queue
]]
function Queue:enqueue(value)
	self.last += 1
	self.queue[self.last] = value
end

--[[
	Remove a value from the queue
]]
function Queue:dequeue()
	if self:isEmpty() then
		return nil
	end
	local value = self.queue[self.first]
	self.queue[self.first] = nil
	self.first += 1
	return value
end

--[[
	Calls `test()` on each element of the queue.
	Returns `true` if and when `test()` does.
]]
function Queue:find(test)
	for _, item in self.queue do
		if test(item) then
			return true
		end
	end
end

--[[
	Returns a copy of the queue as a list table.
]]
function Queue:list(test)
	local list = {}
	for i = self.first, self.last do
		table.insert(list, self.queue[i])
	end
	return list
end

-- QUEUE IMPLEMENTATION END

-- BLOCKING QUEUE IMPLEMENTATION

local BlockingQueue = {}
BlockingQueue.__index = BlockingQueue

function BlockingQueue.new()
	local self = setmetatable({}, BlockingQueue)
	self.first = 0
	self.last = -1
	self.queue = {}
	self.serviceThread = nil
	return self
end

-- Check if the queue is empty (no external use case)
function BlockingQueue:_isEmpty()
	return self.first > self.last
end

-- Internal Dequeue()
function BlockingQueue:_dequeue()
	local value = self.queue[self.first]
	self.queue[self.first] = nil
	self.first += 1
	return value
end

-- Add a value to the queue
function BlockingQueue:enqueue(value)
	self.last += 1
	self.queue[self.last] = value
	if self.takeThread then
		coroutine.resume(self.takeThread, self:_dequeue())
	end
end

-- Remove a value from the queue or wait until there is one.
function BlockingQueue:dequeue()
	if not self:_isEmpty() then
		return self:_dequeue()
	end
	self.takeThread = coroutine.running()
	local value = coroutine.yield()
	self.takeThread = nil
	return value
end

-- Calls `test()` on each element of the queue.
-- Returns `true` if and when `test()` does.
function BlockingQueue:find(test)
	for _, item in self.queue do
		if test(item) then
			return true
		end
	end
end

-- BLOCKING QUEUE IMPLEMENTATION END

--[[
This is a special implementation of the JS `map` function
(https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Array/map).

Given that a LUA table can be either a `dict` or `list`
this function has been coded to allow either straight mappings or convertion between the 2 forms.
The `callback` function can except 3 parameters:
the current `value` and it's `key` and a numerical `index` of the current list position
(could be the same as `key`).
The `callback` function should always the return new value but can optional return the new key
(if omitted the current key is used). The following examples are given to illustrate usage.

	Example 1: mapping a `list` to a `list`:
	("doubling" the list)
	```
	local t1 = {1, 2, 3}
	local t2 = map(t, function(value) return value * 2 end)
	print(t2) -> {2, 4, 6}
	```

	Example 2: mapping a `dict` to a `dict`:
	(swapping the key and value)
	```
	local t1 = {a = 'x', b = 'y'}
	local t2 = map(t, function(value, key) return key, value end)
	print(t2) -> {x = 'a', y = 'b'}
	```

	Example 3: mapping a `dict` to a `list`
	(making a list of the keys):
	```
	local t1 = {a = 1, b = 2}
	local t2 = map(t, function(value, key, index) return key, index end)
	print(t2) -> {'a', 'b'}
	```

	Example 4: mapping a `list` to a `dict`
	(indexing a list of object by one of their fields):
	```
	local t1 = {{id = 1, name = 'sim'}, {id = 2, name = 'mike'}}
	local t2 = map(t, function(value) return value.name, value.id end)
	print(t2) -> {1 = 'sim', 2 = 'mike'}
	```
]]
function map(table_, callback)
	local result = {}
	local index = 1
	for key, value in table_ do
		local newValue, newKey = callback(value, key, index)
		result[newKey or key] = newValue
		index += 1
	end
	return result
end

--[[
	This is an special implementation of the JS `filter` function
	(https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Array/filter).

	Given that a LUA table can be either a `dict` or `list`
	this function filters on both `value` and `key` as both are available to the `callback` .
]]
function filter(table_, callback)
	local result = {}
	for key, value in table_ do
		if callback(value, key) then
			result[key] = value
		end
	end
	return result
end

--[[
	Debounces `callback()` by `duration`. If `leading`, then `callback()`
	is called before the duration.
]]
function debounce(duration, callback, leading)
	if leading then
		local now = 0
		return function(...)
			if DateTime.now().UnixTimestampMillis >= (now + duration * 1000) then
				now = DateTime.now().UnixTimestampMillis
				callback(...)
			end
		end
	end
	local thread = nil
	return function(...)
		local params = ...
		if thread then
			task.cancel(thread)
		end
		thread = task.delay(duration, function()
			thread = nil
			callback(params)
		end)
	end
end

--[[
	This function merges `table2` into `table1` and returns the new table (non-mutating).
	The function is recursive so items in both tables with the same list will also be merged
	(and so on). Items on `table2` have priority so:

		`merge({a = 1}, {a = 2})` will return `{a = 2}`

	https://stackoverflow.com/questions/1283388/how-to-merge-two-tables-overwriting-the-elements-which-are-in-both
]]
function merge(table1, table2)
	local tm = table.clone(table1)
	for k,v in pairs(table2) do
		if type(v) == "table" then
			if type(tm[k]) == "table" then
				tm[k] = merge(tm[k], table2[k])
			else
				tm[k] = v
			end
		else
			tm[k] = v
		end
	end
	return tm
end

--[[
	Allows you to extend `Instance` objects, etc. Based on
	https://devforum.roblox.com/t/wrapping-with-metatables-or-how-to-alter-the-functionality-of-roblox-objects-without-touching-them/221611
]]
local extend = function(userdata, extension)
	if type(userdata) ~= "userdata" then
		error("currently only extends `userdata` objects")
	end

	local fake = newproxy(true)
	local meta = getmetatable(fake)

	meta.__index = function(s,k)
		-- if there's an extension, return it 
		if extension[k] then
			return extension[k]
		end
		-- TODO assumes that all functions are methods which might not be true
		if type(userdata[k]) == "function" then
			return function(self, ...)
				return userdata[k](userdata, ...)
			end
		end 
		return userdata[k]
	end

	-- allowing us to set values
	meta.__newindex = function(s,k,v)
		userdata[k] = v
	end

	meta.__tostring = function(s)
		return tostring(userdata)
	end

	return fake
end

--[[
	Repeatedly invokes `callback` after `duration` (in seconds). Non-blocking.
	The default `duration` is 1 second.
	If `onError` is defined then any errors are reported by this route.
]]
local function onInterval(callback, duration, onError)
	duration = duration or 1
	coroutine.wrap(function()
		while true do
			local status, err = pcall(callback)
			if (not status) and onError then
				onError(err)
			end
			task.wait(duration)
		end
	end)()
end

--[[
	Iterates over a table of `properties` and recursively sets them on a `node`.
	Returns the `node` for chaining.
]]
function setProperties(node, properties)
	properties = properties or {}
	for property, value in pairs(properties) do
		if type(value) == "table" then
			setProperties(node[property], value)
		else
			node[property] = value
		end
	end
	return node
end

--[[
	A sine function that accepts degrees
]]
local function sin(deg)
	return math.sin(math.rad(deg))
end

--[[
	A cosine function that accepts degrees
]]
local function cos(deg)
	return math.cos(math.rad(deg))
end

--[[
	If a string is longer than a certain length, 
	take off trailing numbers, and if that's not enough, 
	replace the last-but-one characters with an apostrophe
]]
local function abbrev(playerName, maxLength)
	while #playerName > maxLength and tonumber(playerName[#playerName]) do 
		playerName = playerName:sub(1, -2)
	end
	if #playerName > maxLength then
		return playerName:sub(1, maxLength - 2) .. "'" .. playerName:sub(-1, -1)
	else
		return playerName
	end
end

-- T IMPLEMENTATION: https://stackoverflow.com/questions/10778812/how-do-i-add-a-method-to-the-table-type

-- a metatable with all the `table` library functions
local tableMT = {
	__index = table.clone(table)
}

--[[
Works the same a the LUA (next)[https://www.lua.org/manual/2.4/node31.html] function.
However, it also takes `filter` as a argument.
The base `next` is repeated called until a result is accepted by `filter`
when it is returned along with it's index (the same as `next`).
]]
tableMT.__index.next = function(table_, filter, index)
	local result
	while true do
		index, result = next(table_, index)
		if not result or filter(result) then
			return index, result
		end
	end
end

--[[
Set a table's metatable to tableMT making it more OO.
]]
local function T(table_)
	return setmetatable(table_, tableMT)
end

-- Give tableMT the `map()` function
-- (after `T()` definition so it can use it to wrap the result table).
tableMT.__index.map = function(table_, callback)
	return T(map(table_, callback))
end

-- Give tableMT the `filter()` function
-- (after `T()` definition so it can use it to wrap the result table).
tableMT.__index.filter = function(table_, callback)
	return T(filter(table_, callback))
end

-- Give tableMT the `merge()` function
-- (after `T()` definition so it can use it to wrap the result table).
tableMT.__index.merge = function(t1, t2)
	return T(merge(t1, t2))
end

-- Assign `merge()` to the `*` operator.
tableMT.__mul = tableMT.__index.merge

-- T IMPLEMENTATION END

return {
	Queue = Queue,
	BlockingQueue = BlockingQueue,
	map = map,
	filter = filter,
	debounce = debounce,
	merge = merge,
	extend = extend,
	onInterval = onInterval,
	setProperties = setProperties,
	sin = sin,
	cos = cos,
	abbrev = abbrev,
	T = T,
	-- replacement for `math.huge` that is compatible with `IntValue`
	huge = 2^62,
}
