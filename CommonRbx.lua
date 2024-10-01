--[[
Copyright 2024 Michael and Simeon Bamford ("Bambros")
Functional Source License, Version 1.1, ALv2 Future License
https://github.com/getsentry/fsl.software/blob/main/FSL-1.1-ALv2.template.md

A set of common Roblox functions to be used across different places. 

Dependencies:
	- ReplicatedFirst.Global (only when running)
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local TweenService = game:GetService("TweenService")
local InsertService = game:GetService("InsertService")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContextActionService = game:GetService("ContextActionService")

--[[
The function returns a ref to the `Global` module
either directly if the game is running or with `LoadAsset()` if in the context of a plugin.
]]
local function getGlobal()
	if RunService:IsRunning() then
		return ReplicatedFirst.Global
	end
	return InsertService:LoadAsset(16258179458):GetChildren()[1]
end

local Global = require(getGlobal())

-- alias
local T, setProperties = Global.T, Global.setProperties

--[[
Sets an `ImageLabel` object with a player's thumbnail.
Repeatedly retries on a seperate thread until the thumbnail is available.
`options` can be set as a table that allows to you choose the `size` and `thumbType`
]]
local function setPlayerThumbnailAsync(playerId: number, imageLabel: ImageLabel, options)
	options = options or {}
	options = T{
		size = Enum.ThumbnailSize.Size150x150,
		thumbType = Enum.ThumbnailType.AvatarBust
	}:merge(options)
	task.spawn(function()
		for i = 1, 10 do
			local content, isReady = Players:GetUserThumbnailAsync(
				playerId, options.thumbType, options.size
			)
			if isReady then
				imageLabel.Image = content
				return
			end
			task.wait(1)
		end
		error(("The thumbnail for player %s failed to load"):format(playerId))
	end)
end

--[[
Helper that sets a table of `properties` on the parts of a `model`.
`deep` decides whether to set the `properties` on all descendants of the model
or just the children.
]]
local function setModelProps(model, properties, deep)
	local parts = deep and model:GetDescendants() or model:GetChildren()
	for _, part in parts do
		if part:IsA("BasePart") then
			for property, value in pairs(properties) do
				part[property] = value
			end
		end
	end
end

--[[
Helper that adds an `event` `handler` to the parts of a `model`.
`deep` decides whether to set the `properties` on all descendants of the model
or just the children.
]]--
local function connectModel(model, event, handler, deep)
	local parts = deep and model:GetDescendants() or model:GetChildren()
	for _, part in parts do
		if part:IsA("BasePart") then
			part[event]:Connect(handler)
		end
	end
end

--[[
Creates an `Instance` of type `className` with `properties` set.
]]
local function createInstance(className, properties)
	return setProperties(Instance.new(className), properties)
end

--[[
Helper for creating a `*Value` object instance.
]]
local function createValue(valueType, parent, name, value)
	return createInstance(valueType .. "Value", {
		Name = name,
		Value = value,
		Parent = parent,
	})
end

--[[
Weld 2 parts together with a `WeldConstraint`.
]]
local function weld(part0, part1, weldName) 
	return createInstance("WeldConstraint", {
		Part0 = part0,
		Part1 = part1,
		Name = weldName or "WeldConstraint",
		Parent = part0,
	})
end

--[[
Rotates `targetCFrame` using the rotation defined by `rotationCFrame`
about a pivot defined by `pivotCFrame`. 
]]
function rotate(targetCFrame, rotationCFrame, pivotCFrame)
	return pivotCFrame * rotationCFrame * pivotCFrame:inverse() * targetCFrame
end

--[[
If `aString` is a number then convert it to a number else return `aString`.
]]
local function convertToNumber(aString)
	local convertedKeyPart = tonumber(aString)
	return convertedKeyPart and convertedKeyPart or aString
end

--[[
Encodes `tableData` as a set on attributes on an `instance`.
Nested data is encoded in the form: key_subkey_subsubkey = value where "_"
is the default `seperator`.
The given `seperator` is disallowed in the data's keys.
]]
local function dumpToAttributes(tableData, instance: Instance, seperator, prefix)
	seperator = seperator or '_'
	for key, value in pairs(tableData) do
		key = tostring(key) -- key could be a number
		assert(key:find(seperator) == nil, key .. " cannot contain " .. seperator)
		key = prefix and prefix .. seperator .. key or key
		if type(value) == "table" then
			dumpToAttributes(value, instance, seperator, key)
		else
			if type(value) ~= 'function' then
				instance:SetAttribute(key, value)
			end
		end
	end
end

--[[
Decodes the attributes of an `instance` created by `dumpToAttributes()`
and returns a table of data.
]]
local function loadFromAttributes(instance: Instance, seperator)
	seperator = seperator or '_'
	local tableData = {}
	for key, value in pairs(instance:GetAttributes()) do
		local keyParts = T(key:split(seperator))
		local lastKey = convertToNumber(keyParts:remove())
		local frame = tableData
		for _, keyPart in ipairs(keyParts) do
			keyPart = convertToNumber(keyPart)
			if not frame[keyPart] then
				frame[keyPart] = {}
			end
			frame = frame[keyPart]
		end
		frame[lastKey] = value
	end
	return tableData
end

--[[
https://create.roblox.com/docs/reference/engine/classes/Sound#IsLoaded
]]
local function loadSound(sound)
	-- Has the sound already loaded?
	if not sound.IsLoaded then
		-- if not, wait until it has been
		sound.Loaded:Wait()
	end
	return sound
end

--[[
Improvement on code sample:
https://create.roblox.com/docs/reference/engine/classes/Pages
]]
local function iterPages(pages)
	-- for resumes this coroutine until there's nothing to go through
	return coroutine.wrap(function()
		while true do
			for _, item in pages:GetCurrentPage() do
				-- Pause loop to let developer handle entry and page number
				coroutine.yield(item)
			end
			if pages.IsFinished then
				break
			end
			pages:AdvanceToNextPageAsync()
		end
	end)
end

--[[
Based on
https://create.roblox.com/docs/workspace/collisions#disabling-character-collisions
-]]
local function moveCharacterToCollisionGroup(character, collisionGroup)
	local function addToCollisionGroupIfPart(instance)
		if instance:IsA("BasePart") then
			instance.CollisionGroup = collisionGroup
		end
	end
	for _, descendant in pairs(character:GetDescendants()) do
		addToCollisionGroupIfPart(descendant)
	end
	character.DescendantAdded:Connect(addToCollisionGroupIfPart)	
end

--[[
Create a new instance `name` in `parent` removing any existing instance, first.
The `className` defaults to "Folder".
]]
local function recreate(parent, name, className)
	className = className or 'Folder'
	local existing = parent:FindFirstChild(name)
	if existing then
		existing:Destroy()
	end
	return createInstance(className, {
		Name = name, Parent = parent
	})
end

local rand = Random.new()

--[[
Wraps Random:NextNumber()
]]
local function random(...)
	return rand:NextNumber(...)
end

--[[
Wraps Random:NextInteger()
]]
local function randomInteger(min, max)
	return rand:NextInteger(min, max)
end

--[[
Randomly chooses an item from a `list`
]]
local function choose(list)
	return list[randomInteger(1, #list)]
end

--[[
Continally spins a `basePart` about an `axis` with a `rotationPeriod` (in seconds)
by cycling 3 tweens of 120 degrees each. The tweens are returned to alloww cancellation.
]]
local function spin(basePart, rotationPeriod, axis)
	axis = axis or 2
	local spinInfo = TweenInfo.new(rotationPeriod / 3, Enum.EasingStyle.Linear)
	local tweens = {}
	for i = 1, 3 do
		local angles = {0, 0, 0}	
		angles[axis] = math.rad(i * 120)
		tweens[i] = TweenService:Create(basePart, spinInfo, {
			CFrame = basePart.CFrame * CFrame.Angles(unpack(angles))
		})
	end
	local function getTweenPlayer(tween)
		return function() tween:Play() end
	end
	for i = 1, 3 do
		tweens[i].Completed:Connect(getTweenPlayer(tweens[i % 3 + 1]))
	end
	tweens[1]:Play()
	return tweens
end

--[[
Return all the descendants of `root` defined by `path`.
These are returned as multiple values in reverse order,
ie. the youngest first.
]]
local function getPathDescendants(root, path)
	local targets = T{}
	local target = root
	for _, pathPart in path:split('.') do
		target = target:WaitForChild(pathPart)
		targets:insert(1, target)
	end
	return unpack(targets)
end

--[[
	This method returns the dot seperated path of `instance` up to
	(but not including) it's `ancestor`.
	If `ancestor` isn't given the whole path is returned.
]]
local function getPath(instance, ancestor)
	local path = instance.Name
	while instance.Parent ~= ancestor do
		instance = instance.Parent
		-- we check in-case instance isn't an ancestor of `ancestor`
		assert(instance ~= nil, path)
		path = instance.Name .. '.' .. path
	end
	return path
end

--[[
Because `StarterGui` scripts run after the character has been created, 
we need this wrapper to cleanly handle `CharacterAdded` events.
]]
local function characterAdded(player, callback)
	player.CharacterAdded:Connect(function(character)
		callback(character)
	end)
	if player.Character then
		callback(player.Character)
	end
end


--[[
(Used by plugins) This function tags a newly created asset as "Secondary"
(which means it's decoration and not critical to game play).
It also deletes any assets named with the same path that have previously been moved to
`ReplicatedStorage.Secondary` by a "Prepare Experience For Deployment" plugin.
]]
local function tagAsSecondary(asset: Instance)
	asset:AddTag("Secondary")
	local folder = ReplicatedStorage:FindFirstChild("Secondary")
	if folder then
		local assetName = getPath(asset)
		local target = folder:FindFirstChild(assetName)
		if target then
			target:Destroy()
		end
	end
end

--[[
This method ensures `callback` is called for any existing children of `instance`
and any added in the future.
]]
local function childAdded(instance: Instance, callback)
	for _, child in ipairs(instance:GetChildren()) do
		callback(child)
	end
	instance.ChildAdded:Connect(callback)
end

local tries = 4

--[[
This is wrapper for `pcall` that retries `tries - 1` time on failure
with an exponential backoff.
Errors are raises in a separate thread so that the current thread continues.
]]
local function pcallRetry(...)
	for try = 1, tries do
		if try ~= 1 then
			task.wait(2 ^ (try - 1))
		end
		local success, response = pcall(...)
		if success then
			return true, response
		else
			local params = HttpService:JSONEncode({...})
			local message = ('pcall %s failed on try %s: %s'):format(params, try, response)
			task.spawn(error, message)
		end
	end
	return false, nil
end

--[[
For a particular `player` this function listens for the completion of a profile load attempt.
If this has already been attempted `callback` is called immeadiately.
The `callback` signature is `callback(profile: Folder, success: boolean)`
where `success` is true if the load attempt was successful.
`profile` is still returned regardless of `success`.
]]
local function onProfileLoadAttempted(player:Player, callback)
	local profile = player:WaitForChild('Profile')
	local loaded = profile:FindFirstChild('Loaded')
	if loaded then
		callback(profile, loaded.Value)
	else
		profile.ChildAdded:connect(function(child)
			if child.Name == 'Loaded' then
				callback(profile, child.Value)
			end
		end)		
	end
end

--[[
Helper function that binds a `key` to a button (single press) control to a `handler`.
`enable` controls whether the function binds or unbinds and `name` identifies the bind.
]]
local function bindKey(enable, name, key, handler)
	if enable then
		ContextActionService:BindAction(
			name,
			function(actionName, inputState, inputObject)
				-- only call the hander when the key is initially pressed
				if actionName == name and inputState == Enum.UserInputState.Begin then
					handler()
				end
				-- TODO bit of a hack to get all handlers bound to this key to fire.
				return Enum.ContextActionResult.Pass
			end,
			false, key
		)
	else
		ContextActionService:UnbindAction(name)
	end
end

return {
	-- alternative to `math.huge` that is compatible with `IntValue`
	huge = 2^62,
	setPlayerThumbnailAsync = setPlayerThumbnailAsync,
	setModelProps = setModelProps,
	connectModel = connectModel,
	createInstance = createInstance,
	createValue = createValue,
	weld=weld,
	rotate = rotate,
	dumpToAttributes = dumpToAttributes,
	loadFromAttributes = loadFromAttributes,
	loadSound = loadSound,
	iterPages = iterPages,
	moveCharacterToCollisionGroup = moveCharacterToCollisionGroup,
	recreate = recreate,
	random = random,
	randomInteger = randomInteger,
	choose = choose,
	spin = spin,
	getPathDescendants = getPathDescendants,
	getPath = getPath,
	characterAdded = characterAdded,
	tagAsSecondary = tagAsSecondary,
	childAdded = childAdded,
	pcallRetry = pcallRetry,
	onProfileLoadAttempted=onProfileLoadAttempted,
	bindKey = bindKey,
}
