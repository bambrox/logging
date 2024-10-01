--[[
Copyright 2024 Michael and Simeon Bamford ("Bambros")
Functional Source License, Version 1.1, ALv2 Future License
https://github.com/getsentry/fsl.software/blob/main/FSL-1.1-ALv2.template.md

A module that allows us to log interesting events to a specific datastore
that can then be retrieved by an external process
(https://create.roblox.com/docs/cloud/open-cloud/usage-data-stores).
To minimize the chance of hitting the datastore rate limit, log messages are put on a local queue
and then periodically saved to the datastore as a packets of messages.

Dependencies:
	- ReplicatedFirst.Global
	- ReplicatedFirst.CommonRbx
	- ReplicatedFirst.Config
]]--

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local ScriptContext = game:GetService("ScriptContext")
local ReplicatedFirst = game:GetService('ReplicatedFirst')
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService('ReplicatedStorage')
local LocalizationService = game:GetService("LocalizationService")

local Global = require(ReplicatedFirst.Global)
local CommonRbx = require(ReplicatedFirst.CommonRbx)

-- alias
local T = Global.T

local Config = T{
	-- How often (in seconds) packets of log messages are stored in the "Logging" datastore. 
	loggingDelay = 3,
	-- How often players' positions are logged (in seconds)
	positionLoggingPeriod = 1,
	-- A debugging switch for when we wish to see all (JSON) messages in studio
	-- but we don't want to store them.
	pretendItsDeployed = false,
	-- The (namespaced) name of the `RemoteEvent` the client uses to communicate messages.
	logEventName = "Logging.log",
}

-- If not in studio then we assume it's deployed.
local isReallyDeployed = not RunService:IsStudio()

-- Flag to log messages as if deployed (which it might be)
local isDeployed = isReallyDeployed or Config.pretendItsDeployed

--[[
Returns a table of all the players' positions keyed on their name. 
]]
local function getPlayerPositions()
	local playerPosns = {}
	for _, player in ipairs(Players:GetPlayers()) do
		playerPosns[player.Name] = {}
		if player.Character then
			local rootPart = player.Character:FindFirstChild("HumanoidRootPart")
			if rootPart then
				playerPosns[player.Name] = {
					X = math.round(rootPart.Position.X),
					Y = math.round(rootPart.Position.Y),
					Z = math.round(rootPart.Position.Z),
				}
			end
		end
	end
	return playerPosns
end

--[[
Convert artibrary parameters into an a timestamped array
]]
local function createMessage(...)
	return {DateTime.now().UnixTimestampMillis, ...}
end

--[[
Calls `SetAsync()` on `dataStore`.
If this call fails then the resulting error will be enqueued for the next store attempt.
TODO:
This is better than what we had before. If this calls fails however, we will lose a message packet.
Possible solutions:
- Re-submit this packet to the queue. This may work. However it also make the next package much larger
  which may increase the chances of a subsequent failure (possibly to 100%). Also it increases the chances
  of losing data at the end.
- Re-establish an external logging endpoint as a failover in the event of an error.
  This should be more reliable but will involve more work.
]]
local function callSetAsync(queue, dataStore, key, value)
	local success, message = pcall(dataStore.SetAsync, dataStore, key, value)
	if not success then
		queue:enqueue(createMessage("error", dataStore.Name, message))
	end
	return success
end

-- DEFINITION OF `log()` (environment dependent)

--[[
We initially define `log()` for the client which simply fires a log event.
TODO:
We note here that client-side logging in it's present form is vulnerable to DOS.
]]
local function log(...)
	ReplicatedStorage:WaitForChild(Config.logEventName):FireServer(...)
end

if RunService:IsServer() then

	if isReallyDeployed then
		-- A packet's place data is an array consisting of
		-- the game's `PlaceId` and the server's `JobId`.
		local placeData = {game.PlaceId, game.JobId}

		-- A reference to the main message logging `DataStore`.
		local dataStore = DataStoreService:GetDataStore("Logging")

		-- A reference to the `OrderDataStore` that maintains
		-- an index of keys to the main `DataStore`.
		local dataStoreIndex = DataStoreService:GetOrderedDataStore("LoggingIndex")

		-- A local queue for collecting log messages to be saves as a single packet.
		local queue = Global.Queue.new()

		--[[
		Every `loggingDelay` we de-queue any/all log messages and store them in "Logging"
		as an array of messages keyed with a timestamp.
		]]
		task.spawn(function()
			while true do
				task.wait(Config.loggingDelay)
				-- add `placeData` at the start of each packet
				local messages = T{placeData}
				while not queue:isEmpty() do
					messages:insert(queue:dequeue())
				end
				if #messages > 1 then
					local timestamp = DateTime.now().UnixTimestampMillis
					local key = ('%s.%s'):format(timestamp, game.JobId:sub(-4))
					local success = callSetAsync(queue, dataStore, key, messages)
					if success then
						-- We also write an entry to "LoggingIndex" as a scalable index
						-- for the main `DataStore` (this is for scalable retrieval).
						callSetAsync(queue, dataStoreIndex, key, timestamp)
					end
				end
			end
		end)

		-- If actually deployed then `log()` enqueues a timestamped message.
		log = function(...)
			queue:enqueue(createMessage(...))
		end
	elseif Config.pretendItsDeployed then
		-- If we are just pretending then print a JSON encoded message. 
		log = function(...)
			print(HttpService:JSONEncode({...}))
		end
	else   
		-- just print the actual message
		log = print
	end
end

-- DEFINITION OF `log()` (environment dependent) END

--[[
A convenience function for logging an "error" level message.
]]
local function logError(...)
	log("error", ...)
end

-- log any errors (on client or server)
ScriptContext.Error:Connect(function(message, trace)
	if RunService:IsServer() then -- Format depends on client vs server
		log("error", "server", message, trace)
	else
		log("error", message, trace)
	end
end)

if RunService:IsServer() then
	-- Create a `RemoteEvent` used by the client to log to the server.
	local logEvent = Instance.new("RemoteEvent")
	logEvent.Name = Config.logEventName
	logEvent.Parent = ReplicatedStorage

	-- listen for client log events	
	logEvent.OnServerEvent:Connect(function(player, messageType, ...)
		log(messageType, player.Name, ...)
	end)

	-- log when a player joins and any friends they have in the game
	Players.PlayerAdded:Connect(function(player)
		log("joined", player.Name, LocalizationService:GetCountryRegionForPlayerAsync(player))
		local friendsPlaying = T{}
		for friend in CommonRbx.iterPages(Players:GetFriendsAsync(player.UserId)) do
			if Players:GetPlayerByUserId(friend.Id) then
				friendsPlaying:insert(friend.Username)
			end
		end
		if #friendsPlaying > 0 then
			log("friends", player.Name, friendsPlaying)
		end
		if isDeployed then
			player.Chatted:Connect(function(msg)
				log("chat", player.Name, msg)
			end)
		end	
	end)
	-- log when a player leaves	
	Players.PlayerRemoving:Connect(function(player)
		log("left", player.Name)
	end)
	
	if isDeployed then
		-- Periodically poll and log the positions of all players
		task.spawn(function()
			while true do
				task.wait(Config.positionLoggingPeriod)
				local positions = getPlayerPositions()
				if next(positions) ~= nil then
					log('positions', nil, positions)
				end
			end
		end)
	end	
end

return {
	log = log,
	logError = logError,
	-- only logs when deployed (or pretending)
	logWhenDeployed = isDeployed and log or function() end,
}
