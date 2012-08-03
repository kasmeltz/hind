--[[
	map_rasterizer.lua
	
	Created AUG-02-2012
]]

local log				= require 'log'
local Object 			= (require 'object').Object
local table				= require 'table_ext'

local pairs
	= pairs
	
module('objects')

MapRasterizer = Object{ _init = { '_map' } }
		
--
--  MapRasterizer constructor
--
function MapRasterizer:_clone(values)
	local o = Object._clone(self,values)
			
	o._profiler = Profiler{}
	
	return o
end

--
-- 	Bresenham line algo
--
local function bresenham(p0,p1,m)
	m[p0.y][p0.x] = 1
	
	local dx = math.abs(p1.x-p0.x)
	local dy = math.abs(p1.y-p0.y)
	
	local sx, sy
	if p0.x < p1.x then sx=1 else sx=-1 end
	if p0.y < p1.y then sy=1 else sy=-1 end
	
	local err = dx-dy
	
	while true do
		m[p0.y][p0.x] = 1
		
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
local function floodfill(m,pt)
	local q = {}
	
	q[#q+1] = pt
	
	while #q>0 do
		local pt = table.remove(q)
		if m[pt.y][pt.x] == 0 then
			m[pt.y][pt.x] = 1
			
			if pt.x > 1 then -- west
				q[#q+1] = p(pt.x-1,pt.y)
			end
			
			if pt.y > 1 then -- north
				q[#q+1] = p(pt.x,pt.y-1)
			end
			
			if pt.x < #m[pt.y] then -- east
 				q[#q+1] = p(pt.x+1,pt.y)
			end
			
			if pt.y < #m then -- south
				q[#q+1] = p(pt.x,pt.y+1)
			end
		end		
	end
end

--
--  Rasterizes the generated map to 2D tiles
--
function MapRasterizer:rasterize(xSize, ySize)
	local profiler = self._profiler
	
	profiler:profile('rasterizing map', function()		
		self._tiles = {}
		for y = 1, ySize do
			self._tiles[y] = {}
		end
	end) -- profile
	
	self:logProfiles()	
end

function MapRasterizer:logProfiles()
	log.log(' === RASTERIZER PROFILE RESULTS === ')
	for k, v in pairs(self._profiler:profiles()) do
		log.log('----------------------------------------------------------------------')
		log.log(k)
		log.log(table.dump(v))
		log.log('----------------------------------------------------------------------')
	end
end