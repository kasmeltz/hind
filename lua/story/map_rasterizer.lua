--[[
	map_rasterizer.lua
	
	Created AUG-02-2012
]]


local Object 			= (require 'object').Object
local log				= require 'log'
local table				= require 'table_ext'
local point				= require 'point'
local double_queue		= require 'double_queue'

local pairs, ipairs, math, io, collectgarbage, print, tostring
	= pairs, ipairs, math, io, collectgarbage, print, tostring
	
require 'profiler'
	
module('objects')

MapRasterizer = Object{ _init = { '_map' } }

local EMPTY_TILE = 0
		
--
--  MapRasterizer constructor
--
function MapRasterizer:_clone(values)
	local o = Object._clone(self,values)
			
	o._profiler = Profiler{}
	
	-- the minmimum rasterizable area
	-- and the size of the rasterizers spatial hash
	o._cellSize = 8
	
	-- this can be set by the caller to
	-- define any relationship between biome names
	-- and tile output
	o._biomeMap = 
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
	
	-- will store the cells to raster
	o._cellsToRaster = {}
	
	return o
end

--
--  Returns a hash value of the supplied point
--  to the nearest coordinates in the map rasterizer cell structure
--
--  Also returns the x and y coordinates that are the
--	the closest cell coordinates to the ones requested
--
function MapRasterizer:hash(x, y)
	local x = math.floor(x / self._cellSize)
	local y = math.floor(y / self._cellSize)
	return y * self._size.x + x, x, y
end

--
--  Converts a point from old coordinates to new
--
function MapRasterizer:convertPoint(p)
	local x = p.x - self._origMin.x
	local y = p.y - self._origMin.y
	local x = math.floor(x / self._origSize.x * self._size.x)
	local y = math.floor(y / self._origSize.y * self._size.y)
	return point:new(x,y)
end

--
--  Adds a center to the proper cell buckets
--
function MapRasterizer:addCenterToBuckets(center)
	
	local function addToBucket(hash)
		if not self._buckets[hash] then
			self._buckets[hash] = {}
		end
		self._buckets[hash][center._id] = center
	end
	
	local minX, maxX, minY, maxY = 
		math.huge, -math.huge, math.huge, -math.huge
		
	local function minMaxPoints(p)
		if p.x < minX then minX = p.x end
		if p.x > maxX then maxX = p.x end
		if p.y < minY then minY = p.y end
		if p.y > maxY then maxY = p.y end
	end

	minMaxPoints(center._rasterPoint)
	for _, co in ipairs(center._corners) do
		minMaxPoints(co._rasterPoint)
	end
		
	for y = minY, maxY, self._cellSize do
		for x = minX, maxX, self._cellSize do
			local hash = self:hash(x,y)
			addToBucket(hash)
		end
	end
end

--
--  Initializes the rasterizer so that it is ready for
--	rasterizing
--
--  Inputs:
--		origMin - the minimim coordinates in the map 
--		origSize - the size of the original map
--		newSize - the size of the rasterized map
--
function MapRasterizer:initialize(origMin, origSize, newSize)
	log.log('==============================================')
	log.log('Initializing rasterizer')
	log.log('Memory before: ' .. collectgarbage('count'))
	
	local profiler = self._profiler
	
	profiler:profile('initializing rasterizer', function()
		self._buckets = {}	
	
		self._origMin = origMin
		self._origSize = origSize
		self._size = newSize
		
		self._tiles = {}
		for y = 1, self._size.y do
			self._tiles[y] = {}
		end
		self._scanLines = {}
		for y = 1, self._size.y do
			self._scanLines[y] = { small_x = 0, large_x = 0}
		end
	
		-- @TODO we need to store the scaled
		-- point values somewhere and not sure
		-- if it should be here or in the 
		-- original graph - for now we will
		-- store scaled values in original graph?		
		-- rescale the centers and corners
		for _, c in pairs(self._map._centers) do
			if not c._ocean then
				c._rasterPoint = self:convertPoint(c._point)
				for _, co in ipairs(c._corners) do
					co._rasterPoint = self:convertPoint(co._point)
				end		
				-- add the centers to the 2d spatial buckets		
				self:addCenterToBuckets(c)
			end
		end	
	end) -- profile
	
	log.log('Number of 2D spatial buckets: ' .. table.count(self._buckets))
	
	log.log('Memory after: ' .. collectgarbage('count'))	
	log.log('Initializing rasterizer complete')
	log.log('==============================================')
end

-- 
--  Rasters a cell ( a convex polygon )
--
function MapRasterizer:rasterCell(cell, value)
	local small_y = cell._corners[1]._rasterPoint.y
	local large_y = cell._corners[1]._rasterPoint.y
	
	-- step 0: clip polygon???
	
	-- step 1: find small and large y's for all of the vertices
	for i = 1, #cell._corners do
		local y = cell._corners[i]._rasterPoint.y
		if y < small_y then
			small_y = y
		elseif y > large_y then 
			large_y = y
		end
	end
	
	-- step 2: array that contains small_x and large_x values for each y
	local delta_y = large_y - small_y + 1
	for i = 1, delta_y do
		self._scanLines[i].small_x = math.huge
		self._scanLines[i].large_x = -math.huge
	end
	
	-- step 3: go through all the lines in this polygon and build min/max x array
	for i = 1, #cell._corners do
		-- last line will link last vertex with the first (index num-1 to 1)
		local ind = (i % #cell._corners) + 1
		
		local p1 = cell._corners[i]._rasterPoint
		local p2 = cell._corners[ind]._rasterPoint
				
		if p2.y ~= p1.y then
			local longD, shortD
			local incXH, incYH, incXL, incYL
			
			-- initializing current line data
			local dx = p2.x - p1.x
			local dy = p2.y - p1.y
			
			if dx >= 0 then
				incXH = 1
				incXL = 1
			else 
				dx = -dx
				incXH = -1
				incXL = -1
			end			
			
			if dy >= 0 then
				incYH = 1
				incYL = 1
			else 
				dy = -dy
				incYH = -1
				incYL = -1
			end
			
			if dx >= dy then
				longD = dx 
				shortD = dy
				incYL = 0
			else		 
				longD = dy  
				shortD = dx
				incXL = 0
			end
			
			local d = 2 * shortD - longD
			local incDL = 2 * shortD
			local incDH = 2 * shortD - 2 * longD
			
			-- initial current x/y values
			local xc = p1.x
			local yc = p1.y
			
			-- step through the current line and remember min/max values at each y
			for j = 1, longD + 1 do
				ind = yc - small_y + 1
				if xc < self._scanLines[ind].small_x then
					self._scanLines[ind].small_x = xc
				end
				if xc > self._scanLines[ind].large_x then
					self._scanLines[ind].large_x = xc
				end				
				-- finding next point on the line ...
				if d >= 0 then
					-- H-type				
					xc = xc + incXH
					yc = yc + incYH
					d = d + incDH
				else		
					-- L-type
					xc = xc + incXL
					yc = yc + incYL
					d = d + incDL
				end
			end							
		end
	end
	
	-- step 4: drawing horizontal line for each y from small_x to large_x including		
	for i = 1, delta_y do
		local y = i + small_y - self._location.y
		if y >= 1 and y <= self._area.y then			
			local sx = self._scanLines[i].small_x - self._location1.x
			local ex = self._scanLines[i].large_x - self._location1.x
			if ex >= 1 and sx <= self._area.x then
				sx = math.max(1, sx)
				ex = math.min(self._area.x, ex)
				for x = sx, ex do			
					self._tiles[y][x] = value
				end			
			end
		end
	end	
end
				
--
--  Rasterizes the generated map to 2D tiles
--
function MapRasterizer:rasterize(location, area)
	local profiler = self._profiler
	
	log.log('==============================================')
	log.log('Rasterizing map')
		
	self._location = location
	self._location1 = point:new(self._location.x - 1, self._location.y - 1)
	self._area = area	
	
	log.log('Blanking tile structure...')	
	local tiles = self._tiles
	profiler:profile('creating tile structure', function()		
		for y = 1, area.y do
			for x = 1, area.x do
				tiles[y][x] = EMPTY_TILE
			end
		end	
	end) -- profile
		
	-- figure out what buckets to raster
	log.log('Deciding what buckets to rasterasize...')	
	local bucketsToRaster = {}		
	profiler:profile('deciding what buckets to rasterasize', function()	
		for y = location.y - self._cellSize, location.y + area.y, self._cellSize do
			for x = location.x - self._cellSize, location.x + area.x, self._cellSize do			
				local hash = self:hash(x,y)
				bucketsToRaster[hash] = self._buckets[hash]								
			end
		end
	end) -- profile

	-- figure out what cells to raster	
	profiler:profile('blanking cell raster table', function()		
		for k, v in pairs(self._cellsToRaster) do
			self._cellsToRaster[k] = nil
		end
	end) -- profile
	
	-- figure out what cells to raster	
	profiler:profile('deciding what cells to rasterasize', function()	
		for hash, bucket in pairs(bucketsToRaster) do			
			for _, c in pairs(bucket) do
				self._cellsToRaster[c._id] = c
			end
		end
	end) -- profile
	
	-- rasteramasize cells
	log.log('Rasteramasizing cells...')
	profiler:profile('rasteramasizing cells', function()	
		for _, c in pairs(self._cellsToRaster) do
			self:rasterCell(c, self._biomeMap[c._biome])
		end
	end) -- profile
		
	log.log('Rasterizing map complete')	
	log.log('==============================================')	
	
	--self:saveMap('rastered.txt', self._tiles)
	self:logProfiles()		
	--self:logDebug()	
	
	return tiles	
end

local tileTypes = 
	{
		'0', '1', '2', '3',
		'4', '5', '6', '7', 
		'8', '9', ']', 'L', 
		'/', '"', '#', '@', 
		'&', '\\', '!', '(', 
		')', '<', '>', '?'
	}
tileTypes[EMPTY_TILE + 1] = ' ' 

--
--  Convert the rasterized map to a string
--
function MapRasterizer.__tostring(self)
	local m = self._tiles
	local s = {}
	for i=1,self._area.y do
		for j=1,self._area.x do
			s[#s+1] = tileTypes[m[i][j]+1]
		end
		s[#s+1] = '\n'
	end
	-- get rid of last \n
	s[#s] = nil
	return table.concat(s, '')
end

--
--	Save the map to a file
--
function MapRasterizer:saveMap(filename, m)
	log.log('Saving map to "'..filename..'"')
	
	local s = self.__tostring(self)	
	local f = io.open(filename,'w')
	f:write(s)
	f:close()
end

--
--  Log the profiler results
--
function MapRasterizer:logProfiles()
	log.log(' === RASTERIZER PROFILE RESULTS === ')
	for k, v in pairs(self._profiler:profiles()) do
		log.log('----------------------------------------------------------------------')
		log.log(k)
		log.log(table.dump(v))
		log.log('----------------------------------------------------------------------')
	end
end

--
--  Log debug information
--  
function MapRasterizer:logDebug()
	local f = io.open('debug.txt', 'w')
	f:write('========================================\n')
	for _, c in pairs(self._cellsToRaster) do
		f:write('CENTER #' .. c._id .. '\n')
		f:write(tostring(c._point))
		f:write('\nCORNERS\n')
		for _, co in pairs(c._corners) do
			f:write(tostring(co._point))
			f:write('\n')
		end
	end	
	f:write('========================================\n')
	f:close()
end