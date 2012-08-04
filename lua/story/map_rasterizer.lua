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

function MapRasterizer:liangBarskyClip(edgeLeft, edgeBottom, edgeRight, edgeTop, p0, p1)
	local t0 = 0.0
	local t1 = 1.0
	local x0src = p0.x
	local y0src = p0.y
	local x1src = p1.x
	local y1src = p1.y
    local xdelta = x1src - x0src
    local ydelta = y1src - y0src
    local p,q,r

	for edge = 0, 3 do
        if edge == 0 then 
			p = -xdelta
			q = -(edgeLeft - x0src)
        elseif edge == 1 then
			p = xdelta
			q = (edgeRight - x0src)
		elseif edge == 2 then
			p = -ydelta
			q = -(edgeBottom - y0src)
		elseif edge == 3 then
			p = ydelta
			q = (edgeTop - y0src)
		end
			
        r = q / p
		-- Don't draw line at all. (parallel line outside)
        if p == 0 and q < 0 then 			
			return nil 
		end 	

        if p < 0 then
			-- Don't draw line at all.
            if r > t1 then 				
				return nil			
			-- Line is clipped!
            elseif r > t0 then 			
				t0 = r 
			end           
        elseif p > 0 then					
			-- Don't draw line at all.
            if r < t0 then
				return nil			
			-- Line is clipped!				
            elseif r < t1 then			
				t1 = r
			end
        end
    end

    return x0src + t0 * xdelta, y0src + t0 * ydelta, 
		x0src + t1 * xdelta, y0src + t1 * ydelta
end
	
--
-- 	Uses bresenham line algo
--
function MapRasterizer:drawEdge(p0,p1,value)
	local m = self._tiles

	-- deal with clipping
	local p0x, p0y, p1x, p1y = 
		self:liangBarskyClip(1, 1, self._newSize.x, self._newSize.y, p0, p1)
		
	if not p0x then return end
	
	p0x = math.floor(p0x)
	p0y = math.floor(p0y)
	p1x = math.floor(p1x)
	p1y = math.floor(p1y)
	
	local dx = math.abs(p1x-p0x)
	local dy = math.abs(p1y-p0y)
	
	local sx, sy
	if p0x < p1x then sx=1 else sx=-1 end
	if p0y < p1y then sy=1 else sy=-1 end
	
	local err = dx-dy
	
	while true do
		m[p0y][p0x] = value
		
		if (p0x == p1x) and (p0y == p1y) then return end
		
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
			
			if pt.x < self._newSize.x then -- east
 				q[#q+1] = point:new(pt.x+1,pt.y)
			end
			
			if pt.y < self._newSize.y then -- south
				q[#q+1] = point:new(pt.x,pt.y+1)
			end
		end		
	end
end

--
--  Returns true if the point should be included in
--	the rasterization
-- 
function MapRasterizer:includePoint(p)
	return p.x >= self._origMin.x and p.x <= self._origMax.x and 
		p.y >= self._origMin.y and p.y <= self._origMax.y
end

--
--  Converts a point from old coordinates to new
--
function MapRasterizer:convertPoint(p)
	local x = p.x - self._origMin.x
	local y = p.y - self._origMin.y
	local x = math.floor(x / self._origScale.x * self._newSize.x) + 1
	x = math.min(self._newSize.x, x)
	local y = math.floor(y / self._origScale.y * self._newSize.y) + 1
	y = math.min(self._newSize.y, y)
	return point:new(x,y)
end

--
--  Rasterizes a cell of the map
--
function MapRasterizer:rasterizeCell(cell)
	local profiler = self._profiler
	
	-- get all of the edges for this cell
	for _, e in pairs(cell._borders) do
		if self:includePoint(e._v1._point) or self:includePoint(e._v2._point) then
			profiler:profile('drawing cell borders', function()
				local r1 = self:convertPoint(e._v1._point)
				local r2 = self:convertPoint(e._v2._point)
				self:drawEdge(r1,r2,self._biomeMap[cell._biome])
			end) -- profile
		end
	end
	local r = self:convertPoint(cell._point)
	profiler:profile('filling cell', function()				
		self:fillCell(r,self._biomeMap[cell._biome])
	end) -- profile	
end

--
--  Rasterizes the generated map to 2D tiles
--
function MapRasterizer:rasterize(origMin, origMax, newSize)
	local profiler = self._profiler
	
	log.log('==============================================')
	log.log('Rasterizing map')
	
	self._origScale = origMax:subtract(origMin)
	self._origMin = origMin
	self._origMax = origMax
	self._newSize = newSize
	
	profiler:profile('creating tile structure', function()			
		self._tiles = {}
		for y = 1, self._newSize.y do
			self._tiles[y] = {}
			for x = 1, self._newSize.x do
				self._tiles[y][x] = EMPTY_TILE
			end
		end	
	end) -- profile
	
	for _, c in pairs(self._map._centers) do
		if not c._ocean then
			if self:includePoint(c._minPoint) or 
				self:includePoint(c._maxPoint) then			
				
				self:rasterizeCell(c)			
			end
		end
	end		
		
	log.log('Rasterizing map complete')	
	log.log('==============================================')	
	
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