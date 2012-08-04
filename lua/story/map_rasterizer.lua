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
	
	--@TODO could add trivial case here if that is mostly what we expect?

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
		
		if (p0x == p1x) and (p0y == p1y) then 
			return p0x, p0y, p1x, p1y 
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
--  Scanline based flood fill
--
function MapRasterizer:floodFillScanline(x, y, width, height, value, diagonal)
	local m = self._tiles
	
	if x < 1 or y < 1 or x > width or y > height then return end
	
	--@TODO I don't thnk we want diagonal fill
	--local diagonal = diagonal or false
	
    local ranges = { { x, x, y, nil, true, true } }	
	
	-- @TODO REMOVE TEST TO SEE WHERE WE START FILLING
    m[y][x] = value
 
    while #ranges > 0 do
        local r = table.remove(ranges)
        local down = r[4] == true
        local up = r[4] == false
 
        -- extendLeft
        local minX = r[1]
        local y = r[3]
        if r[5] then
            while minX > 1 and m[y][minX - 1] == EMPTY_TILE do
                minX = minX - 1
				m[y][minX] = value
            end
        end
        local maxX = r[2]
        -- extendRight
        if r[6] then
            while maxX < width and m[y][maxX + 1] == EMPTY_TILE do
                maxX = maxX + 1
				m[y][maxX] = value
            end
        end
 
		-- @TODO we don't want diagonal do we?
        --if(diagonal) {
            --// extend range looked at for next lines
            --if(minX>0) minX&#8211;;
            --if(maxX<width-1) maxX++;
        --}		
        --else {
		-- extend range ignored from previous line
		r[1] = r[1] - 1
		r[2] = r[2] + 1
        --}
 
        local function addNextLine(newY, isNext, downwards) 
            local rMinX = minX
            local inRange = false
            for x = minX, maxX do
                -- skip testing, if testing previous line within previous range
                local empty = (isNext or (x < r[1] or x > r[2])) and m[newY][x] == EMPTY_TILE
                if not inRange and empty then
                    rMinX = x
                    inRange = true
                elseif inRange and not empty then
                    ranges[#ranges + 1] = { rMinX, x - 1, newY, downwards, rMinX == minX, false }
                    inRange = false
                end
                if inRange then	
					m[newY][x] = value
                end
                -- skip
                if not isNext and x == r[1] then
                    x = r[2]
                end
            end
            if inRange then
                ranges[#ranges + 1] = { rMinX, x - 1, newY, downwards, rMinX == minX, true }
            end
        end
 
        if y < height then
            addNextLine(y + 1, not up, true)
		end
        if y > 1 then
            addNextLine(y - 1, not down, false)
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
	
	q[#q+1] = x
	q[#q+1] = y
	
	while #q>0 do
		local x = table.remove(q)
		local y = table.remove(q)
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
			
			if x < self._newSize.x then -- east
 				q[#q+1] = x+1
				q[#q+1] = y
			end
			
			if y < self._newSize.y then -- south
				q[#q+1] = x
				q[#q+1] = y+1
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
--  Converts a point from old coordinates to new
--
function MapRasterizer:convertPoint(x, y)
	local x = x - self._origMin.x
	local y = y - self._origMin.y
	local x = math.floor(x / self._origScale.x * self._newSize.x) + 1
	local y = math.floor(y / self._origScale.y * self._newSize.y) + 1
	return point:new(x,y)
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
		if self:includePoint(e._v1._point.x, e._v1._point.y) or 
			self:includePoint(e._v2._point.x, e._v2._point.y) then
			
			local r1 = self:convertPoint(e._v1._point.x, e._v1._point.y)
			local r2 = self:convertPoint(e._v2._point.x, e._v2._point.y)
			local p0x, p0y, p1x, p1y = self:drawEdge(r1,r2,self._biomeMap[cell._biome])
			
			-- set the point to start filling
			if self._pointsToFill[cell._id] == true and p0x then
				local r =  self:convertPoint(cell._point.x, cell._point.y)
				log.log('WE GOT HERE!!!!!!')
				if p0x < r.x then 
					p0x = p0x + 1 
				elseif p0x > r.x then 
					p0x = p0x - 1 				
				end
				if p0y < r.y then 
					p0y = p0y + 1 
				elseif p0y > r.y then 
					p0y = p0y - 1 				
				end				
				self._pointsToFill[cell._id] = point:new(p0x, p0y)
			end					
		end
	end
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
	
	-- @TODO find a way to make this part more efficient
	-- 2d spatial hashing of polygon centers?
	-- or something else?
	self._cellsToInclude = {}	
	self._pointsToFill = {}
	profiler:profile('deciding what cells to rasterize', function()	
		for _, c in pairs(self._map._centers) do
			if not c._ocean then
				if self:includePoint(c._point.x, c._point.y) then
					self._cellsToInclude[c._id] = c
					self._pointsToFill[c._id] = self:convertPoint(c._point.x, c._point.y)
				elseif self:includePoint(c._minPoint.x, c._minPoint.y) then
					self._cellsToInclude[c._id] = c
					self._pointsToFill[c._id] = true
				elseif self:includePoint(c._minPoint.x, c._maxPoint.y) then 
					self._cellsToInclude[c._id] = c
					self._pointsToFill[c._id] = true
				elseif self:includePoint(c._maxPoint.x, c._minPoint.y) then
					self._cellsToInclude[c._id] = c
					self._pointsToFill[c._id] = true
				elseif self:includePoint(c._maxPoint.x, c._maxPoint.y) then
					self._cellsToInclude[c._id] = c
					self._pointsToFill[c._id] = true
				end				
			end
		end
	end) -- profile
										
	profiler:profile('drawing cell borders', function()	
		for _, c in pairs(self._cellsToInclude) do
			self:rasterizeCell(c)
		end
	end) -- profile
		
	self:saveMap('prefill.txt')
	
	profiler:profile('filling cells', function()			
		for id, pt in pairs(self._pointsToFill) do
			if pt ~= true then
				local c = self._cellsToInclude[id]
				--self:fillCell(pt.x, pt.y, self._biomeMap[c._biome])
				self:floodFillScanline(pt.x, pt.y, 
					self._newSize.x, self._newSize.y, self._biomeMap[c._biome])					
			end
		end
	end) -- profile	

	-- @todo remove test to see wtf is happening with filling
	for id, pt in pairs(self._pointsToFill) do
		local c = self._cellsToInclude[id]
		local r
		if self:includePoint(c._point.x, c._point.y) then
			r = self:convertPoint(c._point.x, c._point.y)
			--self._tiles[r.y][r.x] = 15
		end
		if pt ~= true then
			if r and pt.x == r.x and pt.y == r.y then
			else
				--self._tiles[pt.y][pt.x] = 16
			end
		end	
	end		
				
	self:saveMap('postfill.txt')
	
	log.log('Rasterizing map complete')	
	log.log('==============================================')	
	
	self:logProfiles()	
end

local tileTypes = 
	{
		' ', '*', '=', '+',
		'A', 'I', 'P', 'Q', 
		'[', 'X', ']', 'L', 
		'/', '"', '#', '@', 
		'&', '\\', '!', '(', 
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