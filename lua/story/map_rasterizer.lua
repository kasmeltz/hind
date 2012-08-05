--[[
	map_rasterizer.lua
	
	Created AUG-02-2012
]]


local Object 			= (require 'object').Object
local log				= require 'log'
local table				= require 'table_ext'
local point				= require 'point'
local double_queue		= require 'double_queue'

local pairs, math, io, collectgarbage, print
	= pairs, math, io, collectgarbage, print
	
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
	
	o._biomeMap = 
	{
		OCEAN = 0,
		LAKE = 3,
		MARSH = 3,
		ICE = 1,
		BEACH = 1,
		SNOW = 1,
		TUNDRA = 1,
		BARE = 1,
		SCORCHED = 6,
		TAIGA = 2,
		SHRUBLAND = 4,
		GRASSLAND = 5,
		TEMPERATE_DESERT = 6,
		TEMPERATE_DECIDUOUS_FOREST = 2,
		TEMPERATE_RAIN_FOREST = 3,
		TROPICAL_RAIN_FOREST = 3,
		TROPICAL_SEASONAL_FOREST = 3,
		SUBTROPICAL_DESERT = 6
	}
	
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

	local hash = self:hash(center._rasterPoint.x, center._rasterPoint.y)
	addToBucket(hash)
	for _, e in pairs(center._borders) do
		local hash = self:hash(e._v1._rasterPoint.x, e._v1._rasterPoint.y)
		addToBucket(hash)
		local hash = self:hash(e._v2._rasterPoint.x, e._v2._rasterPoint.y)
		addToBucket(hash)
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
	
		-- @TODO we need to store the scaled
		-- center values somewhere and not sure
		-- if it should be here or in the 
		-- original graph - for now we will
		-- store scaled values in original graph?		
		-- rescale the centers and egdes
		for _, c in pairs(self._map._centers) do
			if not c._ocean then
				c._rasterPoint = self:convertPoint(c._point)
				for _, e in pairs(c._borders) do
					e._v1._rasterPoint = self:convertPoint(e._v1._point)
					e._v2._rasterPoint = self:convertPoint(e._v2._point)
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

function MapRasterizer:liangBarskyClip(edgeLeft, edgeTop, edgeRight, edgeBottom, x0, y0, x1, y1)
	local px = x1 - x0
	local py = y1 - y0
	local t0 = 0
	local t1 = 1
	
	local function pqClip(dp, dd)
		if dp == 0 then
			if dd < 0 then
				return false
			end
		else
			local a = dd / dp
			if dp < 0 then
				if a > t1 then
					return false
				elseif a > t0 then
					t0 = a
				end
			else
				if a < t0 then
					return false
				elseif a < t1 then
					t1 = a
				end
			end
		end
		return true
	end

	if pqClip(-px, x0 - edgeLeft) then
		if pqClip(px, edgeRight - x0) then
			if pqClip(-py, y0 - edgeTop) then
				if pqClip(py, edgeBottom - y0) then
					if t1 < 1 then
						x1 = x0 + t1 * px
						y1 = y0 + t1 * py
					end
                    if t0 > 0 then
						x0 = x0 + t0 * px
						y0 = y0 + t0 * py
                    end
                    return x0, y0, x1, y1
				end
			end
		end
	end
	return false
end
	
--
-- 	Uses bresenham line algo
--
function MapRasterizer:drawEdge(x0,y0,x1,y1,value,justClip)
	local m = self._tiles

	--log.log('Before clipping drawing edge from: ' .. x0 .. ', ' .. y0 .. ' to ' .. x1 .. ', ' .. y1)	
	
	-- deal with clipping
	local p0x, p0y, p1x, p1y = 
		self:liangBarskyClip(1, 1, self._area.x, self._area.y, x0, y0, x1, y1)

	if not p0x then 
		--log.log('Line was fully clipped!') 
		return 
	end
	
	--log.log('Before int drawing edge from: ' .. p0x .. ', ' .. p0y .. ' to ' .. p1x .. ', ' .. p1y)	
	
	p0x = math.floor(p0x)
	p0y = math.floor(p0y)
	p1x = math.floor(p1x)
	p1y = math.floor(p1y)
	
	--log.log('After int drawing edge from: ' .. p0x .. ', ' .. p0y .. ' to ' .. p1x .. ', ' .. p1y)		
	
	if justClip then return p0x, p0y, p1x, p1y end
	
	local sx = p0x
	local sy = p0y
	
	local dx = math.abs(p1x-p0x)
	local dy = math.abs(p1y-p0y)
	
	local sx, sy
	if p0x < p1x then sx=1 else sx=-1 end
	if p0y < p1y then sy=1 else sy=-1 end
	
	local err = dx-dy
	
	while true do
		m[p0y][p0x] = value
		
		if (p0x == p1x) and (p0y == p1y) then 
			return sx, sy
		end
		
		local e2 = 2*err
		if e2 > -dy then
			err = err-dy
			p0x = p0x+sx
		end
		
		if e2 < dx then
			err = err+dx
			p0y = p0y+sy
		end
	end
end

--
-- Simple flood fill. 
--
-- The 80s want this algorithm back. Uses a queue instead of being recursive.
--
-- Params
--   m, a map (table of tables)
--  pt, a p()-generated starting point
--
function MapRasterizer:fillCell(x, y, value)
	local m = self._tiles
	local q = {}
	
	if not x or not y or x < 1 or x > self._area.x or y < 1 or y > self._area.y then 
		return 
	end

	q[#q+1] = x
	q[#q+1] = y
	
	while #q>0 do
		local y = table.remove(q)
		local x = table.remove(q)
		if m[y][x] == EMPTY_TILE then
			m[y][x] = value
			
			if x > 1 then -- west
				q[#q+1] = x-1
				q[#q+1] = y
			end
			
			if y > 1 then -- north
				q[#q+1] = x
				q[#q+1] = y-1
			end
			
			if x < self._area.x then -- east
 				q[#q+1] = x + 1
				q[#q+1] = y
			end
			
			if y < self._area.y then -- south
				q[#q+1] = x
				q[#q+1] = y + 1
			end
		end		
	end
end

--
--  Returns true if the point should be included in
--	the rasterization
-- 
function MapRasterizer:includePoint(x,y)
	return x >= self._origMin.x and x <= self._origMax.x and 
		y >= self._origMin.y and y <= self._origMax.y
end

--
--  Rasterizes a cell of the map
--
--	@TODO make the lines less straight and more zig zaggy?
--	if this is the appropriate place to do that?
--
function MapRasterizer:rasterizeCell(cell)
	local profiler = self._profiler	
	-- get all of the edges for this cell
	for _, e in pairs(cell._borders) do		
		local x0 = e._v1._rasterPoint.x - self._location1.x
		local y0 = e._v1._rasterPoint.y - self._location1.y
		local x1 = e._v2._rasterPoint.x - self._location1.x
		local y1 = e._v2._rasterPoint.y - self._location1.y
		
		-- draw the edge and get the clipped values
		local p0x, p0y, p1x, p1y = self:drawEdge(
			x0,y0,x1,y1,self._biomeMap[cell._biome], self._edgesDrawn[e])
				
		-- set the point to start filling
		if not self._pointsToFill[cell] and p0x then
			if p0x < cell._rasterPoint.x - self._location1.x then 
				p0x = p0x + 1 
			elseif p0x > cell._rasterPoint.x - self._location1.x then 
				p0x = p0x - 1 				
			end
			if p0y < cell._rasterPoint.y - self._location1.y then 
				p0y = p0y + 1 
			elseif p0y > cell._rasterPoint.y - self._location1.y then 
				p0y = p0y - 1 				
			end				
			
			p0x = math.max(1,p0x)
			p0x = math.min(self._area.x,p0x)
			p0y = math.max(1,p0y)
			p0y = math.min(self._area.y,p0y)
			
			self._pointsToFill[cell] = point:new(p0x, p0y)
		end	
		
		self._edgesDrawn[e] = true
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
	
	-- @TODO is there a way to re-use the tile structure so that we don't have to recreate it every time?
	-- definitely, but we need to decide if it is required for optimization purposes
	log.log('Creating tile structure...')	
	local tiles = self._tiles
	profiler:profile('creating tile structure', function()		
		for y = 1, area.y do
			for x = 1, area.x do
				tiles[y][x] = EMPTY_TILE
			end
		end	
	end) -- profile
		
	-- figure out what buckets to raster
	local bucketsToRaster = {}		
	profiler:profile('deciding what buckets to rasterasize', function()	
		for y = location.y, location.y + area.y - 1, self._cellSize do
			for x = location.x, location.x + area.x - 1, self._cellSize do			
				local hash = self:hash(x,y)
				bucketsToRaster[hash] = self._buckets[hash]								
			end
		end
	end) -- profile
	
	
	-- will store the points to fill
	self._pointsToFill = {}
	self._cellsToRaster = {}
	self._edgesDrawn = {}
	
	-- figure out what cells to raster	
	profiler:profile('deciding what cells to rasterasize', function()	
		for hash, bucket in pairs(bucketsToRaster) do			
			for _, c in pairs(bucket) do
				self._cellsToRaster[c._id] = c
			end
		end
	end) -- profile
	
	-- draw cell borders
	log.log('Drawing cell borders...')
	profiler:profile('drawing cell borders', function()	
		for _, c in pairs(self._cellsToRaster) do
			local r = point:new(c._rasterPoint.x, c._rasterPoint.y)
			r.x = r.x - self._location1.x
			r.y = r.y - self._location1.y
			if r.x >= 1 and r.x <= self._area.x and r.y >= 1 and r.y <= self._area.y then
				self._pointsToFill[c] = r
			end
			self:rasterizeCell(c)			
		end
	end) -- profile
	
	--self:saveMap('prefill.txt')
	
	-- fill cells
	log.log('Filling cells...')
	profiler:profile('filling cells', function()	
		for c, pt in pairs(self._pointsToFill) do
			self:fillCell(pt.x, pt.y, self._biomeMap[c._biome])
		end
	end) -- profile	

	--[[
	-- @todo remove test to see wtf is happening with filling
	for c, pt in pairs(self._pointsToFill) do
		local r = c._rasterPoint
		local x = r.x - self._location1.x
		local y = r.y - self._location1.y
		if x >= 1 and x <= self._area.x and y >=1 and y <= self._area.y then
			self._tiles[y][x] = 15			
		end
		if pt.x ~= x and pt.y ~= y then
			self._tiles[pt.y][pt.x] = 16
		end			
	end
	]]
	
	--self:saveMap('postfill.txt')	
	
	log.log('Rasterizing map complete')	
	log.log('==============================================')	
	
	self:logProfiles()	
	
	return tiles	
end

local tileTypes = 
	{
		'W', '*', '=', '+',
		'A', 'I', 'P', 'Q', 
		'[', 'X', ']', 'L', 
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