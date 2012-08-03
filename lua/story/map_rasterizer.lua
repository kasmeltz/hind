--[[
	map_rasterizer.lua
	
	Created AUG-02-2012
]]

local log				= require 'log'
local Object 			= (require 'object').Object
local table				= require 'table_ext'
local point				= require 'point'
local double_queue		= require 'double_queue'

local pairs, math, io
	= pairs, math, io
	
module('objects')

MapRasterizer = Object{ _init = { '_map' } }

local EMPTY_TILE = 0
		
--
--  MapRasterizer constructor
--
function MapRasterizer:_clone(values)
	local o = Object._clone(self,values)
			
	o._profiler = Profiler{}
	
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
-- 	Uses bresenham line algo
--
function MapRasterizer:drawEdge(p0,p1,value)
	local m = self._tiles

	m[p0.y][p0.x] = value
	
	local dx = math.abs(p1.x-p0.x)
	local dy = math.abs(p1.y-p0.y)
	
	local sx, sy
	if p0.x < p1.x then sx=1 else sx=-1 end
	if p0.y < p1.y then sy=1 else sy=-1 end
	
	local err = dx-dy
	
	while true do
		m[p0.y][p0.x] = value
		
		if (p0.x == p1.x) and (p0.y == p1.y) then return end
		
		local e2 = 2*err
		if e2 > -dy then
			err = err-dy
			p0.x = p0.x+sx
		end
		
		if e2 < dx then
			err = err+dx
			p0.y = p0.y+sy
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
function MapRasterizer:fillCell(pt,value)
	local m = self._tiles
	local q = double_queue:new()
	
	q[#q+1] = pt
	
	while #q>0 do
		local pt = table.remove(q)
		if m[pt.y][pt.x] == EMPTY_TILE then
			m[pt.y][pt.x] = value
			
			if pt.x > 1 then -- west
				q[#q+1] = point:new(pt.x-1,pt.y)
			end
			
			if pt.y > 1 then -- north
				q[#q+1] = point:new(pt.x,pt.y-1)
			end
			
			if pt.x < #m[pt.y] then -- east
 				q[#q+1] = point:new(pt.x+1,pt.y)
			end
			
			if pt.y < #m then -- south
				q[#q+1] = point:new(pt.x,pt.y+1)
			end
		end		
	end
end

--
--  Converts a point from old coordinates to new
--
function MapRasterizer:convertPoint(p)
	if  p.x >= 0 and p.y >= 0 and 
		p.x <= self._origSize.x and p.y <= self._origSize.y then
		local x = math.floor(p.x / self._origSize.x * self._newSize.x) + 1
		x = math.min(self._newSize.x, x)
		local y = math.floor(p.y / self._origSize.y * self._newSize.y) + 1
		y = math.min(self._newSize.y, y)
		return point:new(x,y)
	end
end

--
--  Rasterizes a cell of the map
--
function MapRasterizer:rasterizeCell(cell, origSize, size)
	-- get all of the edges for this cell
	for _, e in pairs(cell._borders) do
		if e._v1 and e._v2 then
			local r1 = self:convertPoint(e._v1._point)
			local r2 = self:convertPoint(e._v2._point)
			if r1 and r2 then
				self:drawEdge(r1,r2,self._biomeMap[cell._biome])
			end
		end
	end
	local r = self:convertPoint(cell._point)
	if r then
		self:fillCell(r,self._biomeMap[cell._biome])
	end
end

--
--  Rasterizes the generated map to 2D tiles
--
function MapRasterizer:rasterize(origSize, newSize)
	local profiler = self._profiler
	
	self._origSize = origSize
	self._newSize = newSize
	
	profiler:profile('rasterizing map', function()		
		self._tiles = {}
		for y = 1, self._newSize.y do
			self._tiles[y] = {}
			for x = 1, self._newSize.x do
				self._tiles[y][x] = EMPTY_TILE
			end
		end
		
		for _, c in pairs(self._map._centers) do
			if not c._ocean then
				self:rasterizeCell(c)
			end
		end
	end) -- profile
	
	self:logProfiles()	
end

local tileTypes = 
	{
		' ', '*', '=', '+',
		'-', '@', 'P', 'Q', 
		'_', 'X', '.', ',', 
		'/', '\\', '"', '^', 
		'&', '#', '!', '(', 
		')', '<', '>', '?'
	}
--
--	Save the map to a file
--
function MapRasterizer:saveMap(filename)
	local m = self._tiles
	
	local f = io.open(filename,'w')
	for i=1,#m do
		for j =1,#m[i] do
			f:write(tileTypes[m[i][j]+1])
		end
		f:write('\n')
	end
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