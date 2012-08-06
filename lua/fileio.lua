--[[
	fileio.lua
	
	Created JUL-23-2012
]]

package.path = package.path .. ';.\\story\\?.lua' 

require 'table_ext'
require 'love.timer'
require 'thread_communicator'
local log = require 'log'
local marshal = require 'marshal'
local thread = love.thread.getThread()
local communicator = objects.ThreadCommunicator{ thread }

require 'overworld_map_generator'
require 'map_rasterizer'
local point 			= require 'point'


require 'map'

local mapGenerator 
local map 
local mapRasterizer 
function makeMap()
	mapGenerator = objects.OverworldMapGenerator{}
	mapGenerator:configure{ lloydCount = 2, pointCount = 20000,
		lakeThreshold = 0.3, size = 1, riverCount = 1000,
		factionCount = 6, seed = os.time(), islandFactor = 0.8,
		landMass = 6, biomeFeatures = 2.5 }
	map = mapGenerator:buildMap()
	mapRasterizer = objects.MapRasterizer{map}
	mapRasterizer._biomeMap = 
	{
		OCEAN = 0,
		LAKE = 1,
		MARSH = 1,
		ICE = 1,
		BEACH = 2,
		SNOW = 2,
		TUNDRA = 2,
		BARE = 2,
		SCORCHED = 2,
		TAIGA = 3,
		SHRUBLAND = 3,
		GRASSLAND = 3,
		TEMPERATE_DESERT = 4,
		TEMPERATE_DECIDUOUS_FOREST = 4,
		TEMPERATE_RAIN_FOREST = 4,
		TROPICAL_RAIN_FOREST = 4,
		TROPICAL_SEASONAL_FOREST = 5,
		SUBTROPICAL_DESERT = 5
	}	
	mapRasterizer:initialize(point:new(0,0), point:new(1,1), point:new(4096,4096))
end

makeMap()

local commands = 
{
	'saveMapCell',
	'saveActor',
	'addActorToCell',	
	'loadMapCell',
	'loadActor',
	'deleteActor'
}

--
--  Receives any message
--
function receiveAll()
	for _, v in ipairs(commands) do
		local msg = communicator:receive(v)
		if msg then		
			return v, msg
		end
	end		
end

--
--  Saves actors to disk
--
function saveActor(id)
	log.log('Save Actor: ' .. id)		
	local actor = communicator:demand('saveActor')
	
	local f = io.open('map/' .. id .. '.act', 'wb')	
	if not f then 
		log.log('There was a problem saving the actor #' .. id)
	end	
	
	f:write(actor)	
	f:close()
end

--
--  Load an actor from disk
--
function loadActor(id)
	log.log('Load Actor: ' .. id)		
	
	local f = io.open('map/' .. id .. '.act', 'rb')	
	if not f then 			
		log.log('There was a problem loading the actor #' .. id)
	end	
	local s = f:read('*all')
	f:close()	
			
	communicator:send('loadedActor', s)
end

--
--  Deletes an actor from disk
--
function deleteActor(id)
	log.log('Delete Actor: ' .. id)		

	local result, err = os.remove('map/' .. id .. '.act')	
	
	if not result and not err:find('No such file or directory') then
		log.log('There was a problem deleting actor #' .. id)
		log.log(err)
	end
end

--
--  Save a map cell to disk
--
function saveMapCell(hash)
	log.log('Save Map Cell: ' .. hash)		
	local tiles = communicator:demand('saveMapCell')
	local area = communicator:demand('saveMapCell')
	local actors = communicator:demand('saveMapCell')

	local f = io.open('map/' .. hash .. '.dat' ,'wb')		
	if not f then 
		log.log('There was a problem saving the map cell #' .. hash)
	end		
	f:write(#tiles)
	f:write('_')
	f:write(tiles)	
	f:write(#area)
	f:write('_')
	f:write(area)
	f:close()
	
	local f = io.open('map/act-' .. hash .. '.dat' ,'wb')		
	if not f then 
		log.log('There was a problem saving the actors for map cell #' .. hash)
	end		
	f:write(actors)	
	f:close()	
end

--
--  Load a map cell from disk
--
function loadMapCell(hash)
	log.log('Load Map Cell: ' .. hash)		
	local x, y = objects.Map.unhash(hash)
	
	log.log('x: ' .. x .. ', y: ' .. y)
	
	local tiles, area, actors
	
	log.log('rasterizing')
	
	mapRasterizer:rasterize(point:new(x,y), point:new(8,8))
	
	log.log('rasterized')
	
	tiles = {}
	for i = 1, 4 do
		tiles[i] = {}
		for y = 1, 8 do
			tiles[i][y] = {}
			for x = 1, 8 do
				tiles[i][y][x] = (18 * mapRasterizer._tiles[y][x]) + 11
			end
		end
	end
	tiles[5] = {}
	tiles[6] = {}
	for y = 1, 8 do
		tiles[6][y] = {}
		for x = 1, 8 do
			tiles[6][y][x] = 0
		end
	end
	
	
	log.log('tiles copied')
	
	tiles = marshal.encode(tiles)
	
	log.log('tiles encoded')
	
	area = 'GRASSLAND'
	
	--[[
	local f = io.open('map/' .. hash .. '.dat', 'rb')
	if not f then 
		log.log('There was a problem loading the cell #' .. hash)
		communicator:send('loadedMapCell', 0)
		return
	end		
	local bytes = f:read('*number')
	f:read(1)
	tiles = f:read(bytes)
	bytes = f:read('*number')
	f:read(1)
	area = f:read(bytes)	
	f:close()	
	]]
	
	local f = io.open('map/act-' .. hash .. '.dat' ,'rb')		
	if not f then 
		log.log('There was a problem loading the actors for cell #' .. hash)
	else
		actors = f:read('*all')
		f:close()
	end
	
	actors = actors or marshal.encode{}
	
	communicator:send('loadedMapCell', hash)
	communicator:send('loadedMapCell', tiles)
	communicator:send('loadedMapCell', area)
	communicator:send('loadedMapCell', actors)
end

--
--  Add an actor to a cell
--
function addActorToCell(id)
	local hash = communicator:demand('addActorToCell')
	log.log('Add actor "' .. id .. '" to cell "' .. hash .. '"')		
	
	local f = io.open('map/act-' .. hash .. '.dat' ,'rb')		
	if not f then 
		log.log('There was a problem reading the actors for cell #' .. hash)
		return
	end
	local actors = f:read('*all')
	f:close()
	
	-- add the actor id to the table of actors for this cell
	actors = marshal.decode(actors)		
	actors[#actors + 1] = id
	actors = marshal.encode(actors)
	
	local f = io.open('map/act-' .. hash .. '.dat' ,'wb')		
	if not f then 
		log.log('There was a problem writing the actors for cell #' .. hash)
		return
	end	
	f:write(actors)				
	f:close()		
end

-- LOOP FOREVER!
log.log('File io server waiting for input...')
while true do
	local result, err = true, nil
	local cmd, msg = receiveAll()
	if cmd == 'saveActor' then
		saveActor(msg)
	elseif cmd == 'loadActor' then
		loadActor(msg)
	elseif cmd == 'deleteActor' then
		deleteActor(msg)
	elseif cmd == 'saveMapCell' then
		saveMapCell(msg)
	elseif cmd == 'loadMapCell' then
		result = pcall(loadMapCell,msg)
	elseif cmd == 'addActorToCell' then
		addActorToCell(msg)
	else
		love.timer.sleep(0.001)
	end
	
	if not result then
		log.log(err)
	end
end