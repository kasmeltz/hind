--[[
	factories.lua
	
	Created JUN-23-2012
]]

require 'tileset'
require 'map'
require 'actor'
require 'actor_item'
require 'animation'
require 'camera'
require 'hero'

module (..., package.seeall)

local actorID = 1000000

--
--  Reads in a lua table from a file
--
local function readTableFromFile(filename)
	local f = io.open(filename, 'r')
	if not f then 
		return nil, 'There was an error loading the table from filename "' 
			.. filename .. '" - the file did not open.'
	end
	local s = f:read('*all')
	f:close()
	
	local t = loadstring('return ' .. s)()
	if not t then
		return nil, 'There was an error loading the table from filename "' 
			.. filename .. '" - the file did not parse properly.'
	end
	
	return t
end

--
--  Returns a new tile set loaded
--	from the provided data file
--
function createTileset(filename)
	local t = readTableFromFile(filename)	
	
	for k, v in ipairs(t._images) do
		t._images[k]._image = love.image.newImageData(v._file)
	end
		
	local ts = tileset:new(t)	
	return ts	
end

--
--  Returns a new map using the
--	provided tileset and size
--
--  Inputs:
--		tileSet	- string
--			the name of the tileset to use for this map
--
function createMap(ts, size)
	return objects.Map{ tileSets[ts] }
end

--
--  Returns a new hero loaded
--	from the provided data file
--
--  Inputs:
--		filename - the name of the data file
--		that describes the actor
--
function createHero(filename)
	local t = readTableFromFile(filename)
	for k, v in pairs(t._animations) do
		local a = createAnimation(v)
		t._animations[k] = a		
	end
	t._id = actorID
	actorID = actorID + 1	
	local a = objects.Hero(t)
	return a
end

--
--  Returns a new actor loaded
--	from the provided data file
--
--  Inputs:
--		filename - the name of the data file
--		that describes the actor
--
function createActor(filename)
	local t = readTableFromFile(filename)
	for k, v in pairs(t._animations) do
		local a = createAnimation(v)
		t._animations[k] = a		
	end
	t._id = actorID
	actorID = actorID + 1	
	local a = objects.Actor(t)
	return a
end

--
--  Returns a new actor loaded
--	from the provided data file
--
--  Inputs:
--		filename - the name of the data file
--		that describes the actor
--
function createActorItem(filename)
	local t = readTableFromFile(filename)
	for k, v in pairs(t._animations) do
		local a = createAnimation(v)
		t._animations[k] = a		
	end
	t._id = actorID
	actorID = actorID + 1		
	local ai = objects.ActorItem(t)
	return ai
end

--
--  Returns a new animation
--	from the provided table
--
--  Inputs:
--		table that describes the animation
--
function createAnimation(t)
	t._tileSet = tileSets[t._tileSet]
	local a = objects.Animation(t)
	return a
end

--
--  Returns a new camera
--
function createCamera()
	local c = camera:new{}
	return c
end

--
--  Returns a floating text
--  
function createFloatingText(text, font, color, position, velocity, aliveTime)
	local ft = objects.FloatingText
		{ text, font, color, position, velocity, aliveTime}
	return ft
end