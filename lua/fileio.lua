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
	mapGenerator:configure{ lloydCount = 2, pointCount = 600000,
		lakeThreshold = 0.3, size = 1, riverCount = 1000,
		factionCount = 6, seed = os.time(), islandFactor = 0.8,
		landMass = 6, biomeFeatures = 2.5 }
	map = mapGenerator:buildMap()
	mapRasterizer = objects.MapRasterizer{map}
	mapRasterizer._biomeMap = 
	{
		OCEAN = 0,
		LAKE = 1,
		MARSH = 2,
		ICE = 3,
		BEACH = 4,
		SNOW = 5,
		TUNDRA = 6,
		BARE = 7,
		SCORCHED = 8,
		TAIGA = 9,
		SHRUBLAND = 10,
		GRASSLAND = 11,
		TEMPERATE_DESERT = 12,
		TEMPERATE_DECIDUOUS_FOREST = 13,
		TEMPERATE_RAIN_FOREST = 14,
		TROPICAL_RAIN_FOREST = 15,
		TROPICAL_SEASONAL_FOREST = 16,
		SUBTROPICAL_DESERT = 17
	}	
	mapRasterizer:initialize(point:new(0,0), point:new(1,1), point:new(8192,8192))
end

--
--  Adds transition (overlay tiles)
--  between base terrain types
--
--  This function assumes that each base tile type 
--	consists of 18 tiles with the following and that the base tile 
--	types start at index 1 and are contiguous in 
--	a tileset
--  
function transitions(tiles)
	local tilesPerType = 18
	
	--  a table that maps the edge number
	--  to a tile index in the tileset
	--  n.b. this table describes some assumptions about the
	--  layout of the tiles 
	local edgeToTileIndex = {}
	
	-- top edge
	edgeToTileIndex[4] = 14
	edgeToTileIndex[6] = 14
	edgeToTileIndex[12] = 14
	edgeToTileIndex[14] = 14
	
	-- bottom edge
	edgeToTileIndex[128] = 8
	edgeToTileIndex[192] = 8
	edgeToTileIndex[384] = 8
	edgeToTileIndex[448] = 8	
		
	-- left edge	
	edgeToTileIndex[16] = 12
	edgeToTileIndex[18] = 12
	edgeToTileIndex[80] = 12
	edgeToTileIndex[82] = 12
	
	-- right edge
	edgeToTileIndex[32] = 10
	edgeToTileIndex[40] = 10
	edgeToTileIndex[288] = 10
	edgeToTileIndex[296] = 10
	
	-- top left edge	
	edgeToTileIndex[20] = 2
	edgeToTileIndex[22] = 2
	edgeToTileIndex[24] = 2
	edgeToTileIndex[28] = 2
	edgeToTileIndex[30] = 2
	edgeToTileIndex[68] = 2
	edgeToTileIndex[72] = 2
	edgeToTileIndex[76] = 2
	edgeToTileIndex[84] = 2
	edgeToTileIndex[86] = 2
	edgeToTileIndex[88] = 2
	edgeToTileIndex[92] = 2
	edgeToTileIndex[94] = 2
	edgeToTileIndex[126] = 2	
	
	-- top right edge
	edgeToTileIndex[34] = 3
	edgeToTileIndex[36] = 3
	edgeToTileIndex[38] = 3
	edgeToTileIndex[44] = 3
	edgeToTileIndex[46] = 3
	edgeToTileIndex[258] = 3	
	edgeToTileIndex[260] = 3
	edgeToTileIndex[262] = 3
	edgeToTileIndex[290] = 3
	edgeToTileIndex[292] = 3
	edgeToTileIndex[294] = 3
	edgeToTileIndex[298] = 3		
	edgeToTileIndex[300] = 3
	edgeToTileIndex[302] = 3	
	edgeToTileIndex[318] = 3
	
	-- bottom left edge
	edgeToTileIndex[130] = 5
	edgeToTileIndex[144] = 5
	edgeToTileIndex[146] = 5
	edgeToTileIndex[208] = 5
	edgeToTileIndex[210] = 5
	edgeToTileIndex[218] = 5
	edgeToTileIndex[272] = 5	
	edgeToTileIndex[274] = 5	
	edgeToTileIndex[386] = 5
	edgeToTileIndex[400] = 5
	edgeToTileIndex[402] = 5	
	edgeToTileIndex[464] = 5
	edgeToTileIndex[466] = 5		
		
	-- bottom right edge
	edgeToTileIndex[96] = 6
	edgeToTileIndex[104] = 6	
	edgeToTileIndex[136] = 6	
	edgeToTileIndex[160] = 6	
	edgeToTileIndex[168] = 6	
	edgeToTileIndex[200] = 6
	edgeToTileIndex[224] = 6
	edgeToTileIndex[232] = 6
	edgeToTileIndex[416] = 6	
	edgeToTileIndex[424] = 6
	edgeToTileIndex[480] = 6
	edgeToTileIndex[488] = 6	
	
	-- bottom right inner edge
	edgeToTileIndex[2] = 15	
		
	-- bottom left inner edge
	edgeToTileIndex[8] = 13
	
	-- top right inner edge
	edgeToTileIndex[64] = 9
	
	-- top left inner edge
	edgeToTileIndex[256] = 7
	
	local sy = #tiles[1]
	local sx = #tiles[1][1]
	
	local edges = {}
	for y = 1, sy do
		edges[y] = {}
		for x = 1, sx do	
			edges[y][x]	= {}
		end
	end
			
	for y = 1, sy do
		for x = 1, sx do			
			local tile = tiles[1][y][x]
			local thisType = math.floor((tile - 1)/tilesPerType)

			local count = 8
			-- considsr all neighbouring tiles
			for yy = y - 1, y + 1 do
				for xx = x - 1, x + 1 do
					-- only work to edge of map
					if yy >= 1 and yy <= sy and
						xx >= 1 and xx <= sx and
						not (y == yy and x == xx) then
							local neighbourTile = tiles[1][yy][xx]
							local neighbourType = math.floor((neighbourTile-1)/tilesPerType)							
							if neighbourType > thisType then								
								local edgeType = edges[yy][xx][2 ^ count]
								if (not edgeType) or (edgeType > thisType) then
									edges[yy][xx][2 ^ count] = thisType
								end
							end
							count = count - 1
					end										
				end
			end		
		end	
	end
	
	for y = 1, sy do
		for x = 1, sx do	
			local edgeList = edges[y][x]	
			local sum = 0
			local edgeType = 0
			local minEdgeType = 99
			for k, v in pairs(edgeList) do
				sum = sum + k
				if v < minEdgeType then
					edgeType = v
					minEdgeType = v
				end
			end
			
			if sum > 0 then
				local idx = edgeToTileIndex[sum] or 4
				tiles[2][y][x] = (edgeType * tilesPerType) + idx
			end
		end	
	end	

	edges = nil
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
	--log.log('Load Map Cell: ' .. hash)		
	local x, y = objects.Map.unhash(hash)
	--log.log('x: ' .. x .. ', y: ' .. y)
	
	local tiles, area, actors
	
	--log.log('rasterizing')
	
	local st = love.timer.getMicroTime()
	mapRasterizer:rasterize(point:new(x,y), point:new(8,8))
	log.log('Rastering took ' .. love.timer.getMicroTime() - st)
	
	--log.log('rasterized')

	local st = love.timer.getMicroTime()
	
	tiles = {}
	for i = 1, 4 do
		tiles[i] = {}
		for y = 1, 8 do
			tiles[i][y] = {}
		end
	end
	
	for y = 1, 8 do
		for x = 1, 8 do
			tiles[1][y][x] = (18 * (mapRasterizer._tiles[y][x])) + 11			
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

	log.log('Creating stupid arse table took ' .. love.timer.getMicroTime() - st)
	
	local st = love.timer.getMicroTime()
	
	transitions(tiles)
	
	log.log('Calculating transitions took ' .. love.timer.getMicroTime() - st)		
		
	--log.log('tiles copied')
	
	local st = love.timer.getMicroTime()
	
	tiles = marshal.encode(tiles)
	
	log.log('Marshal encoding took ' .. love.timer.getMicroTime() - st)
	
	--log.log('tiles encoded')
	
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