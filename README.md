# logging
Roblox logging quick start:

In roblox studio, for an experience you want logging for:

Copy these 3 lua files into 'ReplicatedFirst' as ModuleScripts:

 - Global.lua
 - CommonRbx.lua
 - Logging.lua

Then, add this line to least one server script:

local Logging = require(ReplicatedFirst.Logging)


By default this will log:
 - X.Y.Z position for every player once per second.
 - any chat messages
 - the joining and leaving of players
 - on joining: country and user interface of players, and relationships to any friends of players who are in game.

If you want to log other things from anywhere in your code, use lines of code like this:

Logging.log("name_of_logging_event", player_name_if_you_call_this_from_a_server_script, anything_else, you, like)

For example:

Logging.log("finished_level", player.Name, level, time_it_took_to_finish_level)

From a client script, you don't need the player name, that will be added automatically, so just:

Logging.log("finished_level", level, time_it_took_to_finish_level)

If Bambros agree to manage your data and insights, then you'll need to give them an API key. 

Create an API key following these instructions (can be tricky, ask for help):

https://create.roblox.com/docs/cloud/open-cloud/usage-data-stores

In particular, use: 

universe-datastores
- create
- list
- read
- update
- delete

ordered_datastores:
- read
- write

security - IP address: 0.0.0.0/0
