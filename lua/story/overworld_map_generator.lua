--[[
	overworld_map_generator.lua
	
	Created AUG-02-2012
]]

local vd 				= require 'vd'
local vdgraph 			= require 'vdgraph'
local double_queue 		= require 'double_queue'
local point				= require 'point'
local log				= require 'log'

require 'perlin'
require 'overworld_map'
require 'profiler'
require 'table_ext'

local Object = (require 'object').Object

local perlin2D = perlin2D

local pairs, table, math
	= pairs, table, math
	
module('objects')

OverworldMapGenerator = Object{}
		
--
--  OverworldMapGenerator
--
function OverworldMapGenerator:_clone(values)
	local o = Object._clone(self,values)
			
	o._profiler = Profiler{}
	
	return o
end

--
--  Configured the map generator
--
function OverworldMapGenerator:configure(params)
	for k, v in pairs(params) do
		self['_' .. k] = v
	end
end

--
--  Creates perlin noise that will be used to 
--	generate the map
-- 
function OverworldMapGenerator:makePerlin()
	self._perlin = perlin2D(self._seed, 256, 256, 
		self._islandFactor, self._landMass, self._biomeFeatures)
end

--
--  Improve the random set of points with Lloyd Relaxation.
--
function OverworldMapGenerator:improveRandomPoints(points)
	--[[
	We'd really like to generate "blue noise". Algorithms:
	1. Poisson dart throwing: check each new point against all
	 existing points, and reject it if it's too close.
	2. Start with a hexagonal grid and randomly perturb points.
	3. Lloyd Relaxation: move each point to the centroid of the
	 generated Voronoi polygon, then generate Voronoi again.
	4. Use force-based layout algorithms to push points away.
	5. More at http://www.cs.virginia.edu/~gfx/pubs/antimony/
	Option 3 is implemented here. If it's run for too many iterations,
	it will turn into a grid, but convergence is very slow, and we only
	run it a few times.
	]]
	for i = 1, self._lloydCount do
		-- generate voronoi values for the current points
		local corners, centers = vd.voronoi(points)
		
		-- start with a whole new table of points
		for k, v in pairs(points.x) do
			points.x[k] = nil
			points.y[k] = nil
		end
		
		for _, center in pairs(centers) do
			local px = 0
			local py = 0
			for k, v in pairs(center) do
				local x = corners.x[k]
				local y = corners.y[k]
				px = px + x
				py = py + y				
			end				
			
			px = px / table.count(center)
			py = py / table.count(center)

			points.x[#points.x + 1] = px 
			points.y[#points.y + 1] = py
		end
	end
	
	return points
end
	
--
--  Returns true if the point is on land
--
function OverworldMapGenerator:islandShape(p)
	local x = math.floor((p.x + 1) * 128)
	local y = math.floor((p.y + 1) * 128)
	x = math.min(x,256)	
	y = math.min(y,256)
	x = math.max(x,1)	
	y = math.max(y,1)
	
	local c = (128 + 40 * self._perlin[y][x]) / 255	
    return c > (0.3 + 0.3 * p:norm() * p:norm())
end
	
--
-- Determine whether a given point should be on the island or in the water.
--
function OverworldMapGenerator:inside(p)
	return self:islandShape(point:new(2*(p.x / self._size - 0.5), 
		2*(p.y / self._size - 0.5)))
end
	
--
--	Determine elevations and water at Voronoi corners. By
--	construction, we have no local minima. This is important for
--	the downslope vectors later, which are used in the river
--	construction algorithm. Also by construction, inlets/bays
--	push low elevation areas inland, which means many rivers end
--	up flowing out through them. Also by construction, lakes
-- 	often end up on river paths because they don't raise the
--  elevation as much as other terrain does.
function OverworldMapGenerator:assignCornerElevations(corners)
	local q = double_queue:new()
	
	for _, c in pairs(corners) do
		c._water = not self:inside(c._point)
	end
  
	for _, c in pairs(corners) do
		if c._border then
			c._elevation = 0
			q:pushright(c)
		else
			c._elevation = math.huge
		end
	end

	-- Traverse the graph and assign elevations to each point. As we
	-- move away from the map border, increase the elevations. This
	-- guarantees that rivers always have a way down to the coast by
	-- going downhill (no local minima)
	while q:count() > 0 do
		local c = q:popleft()	
		for _, s in pairs(c._adjacent) do
			-- Every step up is epsilon over water or 1 over land. The
			-- number doesn't matter because we'll rescale the
			-- elevations later.
			local newElevation = 0.01 + c._elevation
			if not c._water and not s._water then
				newElevation = newElevation + 1
			end
			-- If this point changed, we'll add it to the queue so
			-- that we can process its neighbors too.
			if newElevation < s._elevation then
				s._elevation = newElevation
				q:pushright(s)
			end
		end
	end
end

 --
 --	Determine polygon and corner types: ocean, coast, land.
 --
function OverworldMapGenerator:assignOceanCoastAndLand(corners, centers)
	-- Compute polygon attributes 'ocean' and 'water' based on the
	-- corner attributes. Count the water corners per
	-- polygon. Oceans are all polygons connected to the edge of the
	-- map. In the first pass, mark the edges of the map as ocean;
	-- in the second pass, mark any water-containing polygon
	-- connected an ocean as ocean.
	local queue = double_queue:new()

	local numWater
	for _, p in pairs(centers) do
		numWater = 0
		for _, q in pairs(p._corners) do
			if q._border then
				p._border = true
				p._ocean = true
				q._water = true
				queue:pushright(p)
			end
			if q._water then
				numWater = numWater + 1
			end
		end
		p._water = p._ocean or numWater >= table.count(p._corners) * self._lakeThreshold
	end
	
	while queue:count() > 0 do
		local p = queue:popleft()
		for _, r in pairs(p._neighbors) do
			if r._water and not r._ocean then
				r._ocean = true
				queue:pushright(r)
			end
		end
	end

	-- Set the polygon attribute 'coast' based on its neighbors. If
	-- it has at least one ocean and at least one land neighbor,
	-- then this is a coastal polygon.
	for _, p in pairs(centers) do
		local numOcean = 0		  
        local numLand = 0
        for _, r in pairs(p._neighbors) do
			if r._ocean then
				numOcean = numOcean + 1
			end
			if not r._water then
				numLand = numLand + 1
			end
		end
		p._coast = numOcean > 0 and numLand > 0
	end
	
	-- Set the corner attributes based on the computed polygon
	-- attributes. If all polygons connected to this corner are
	-- ocean, then it's ocean; if all are land, then it's land;
	-- otherwise it's coast.
	for _, q in pairs(corners) do
		local numOcean = 0
		local numLand = 0
		for _, p in pairs(q._touches) do
			if p._ocean then
				numOcean = numOcean + 1
			end
			if not p._water then
				numLand = numLand + 1
			end
		end		
		q._ocean = numOcean == table.count(q._touches)
		q._coast = numOcean > 0 and numLand > 0
		q._water = q._border or (numLand ~= table.count(q._touches) and not q._coast)
	end
end

--
--	Create an array of polygons that are on land only, for use by
--  algorithms that work only on land.  
--
function OverworldMapGenerator:landPolys(master)
	local locations = {}
	for _, c in pairs(master) do
		if not c._ocean and not c._coast then
			locations[#locations+1] = c
		end
	end      
	return locations
end

--
-- 	Change the overall distribution of elevations so that lower
--	elevations are more common than higher
--	elevations. Specifically, we want elevation X to have frequency
--	(1-X).  To do this we will sort the corners, then set each
-- 	corner to its desired elevation.
function OverworldMapGenerator:redistributeElevations(locations)
      -- SCALE_FACTOR increases the mountain area. At 1.0 the maximum
      -- elevation barely shows up on the map, so we set it to 1.1
      local SCALE_FACTOR = 1.1

      table.sort(locations, function(a,b) return a._elevation < b._elevation end)
	  
      for i = 1, #locations do
        -- Let y(x) be the total area that we want at elevation <= x.
        -- We want the higher elevations to occur less than lower
        -- ones, and set the area to be y(x) = 1 - (1-x)^2.
        local y = i / #locations
        -- Now we have to solve for x, given the known y.
        --  *  y = 1 - (1-x)^2
        --  *  y = 1 - (1 - 2x + x^2)
        --  *  y = 2x - x^2
        --  *  x^2 - 2x + y = 0
        -- From this we can use the quadratic equation to get:
        local x = math.sqrt(SCALE_FACTOR) - math.sqrt(SCALE_FACTOR*(1-y))
        if x > 1.0 then 
			x = 1.0
		end
        locations[i]._elevation = x
      end
end

--
--	Polygon elevations are the average of the elevations of their corners.
--
function OverworldMapGenerator:assignPolygonElevations(centers)
	for _, p in pairs(centers) do
		local sumElevation = 0.0
        for _, q in pairs(p._corners) do
			sumElevation = sumElevation + q._elevation
		end
		p._elevation = sumElevation / table.count(p._corners)
   end
end 

--
--  Calculate downslope pointers.  At every point, we point to the
-- 	point downstream from it, or to itself.  This is used for
--	generating rivers and watersheds.
--
function OverworldMapGenerator:calculateDownslopes(corners)
	local r
	for _, q in pairs(corners) do
		r = q
		for _, s in pairs(q._adjacent) do
			if s._elevation <= r._elevation then
				r = s
			end
		end
		q._downslope = r
	end
end
	
--	Calculate the watershed of every land point. The watershed is
--	the last downstream land point in the downslope graph. TODO:
--	watersheds are currently calculated on corners, but it'd be
--	more useful to compute them on polygon centers so that every
--	polygon can be marked as being in one watershed.
 function OverworldMapGenerator:calculateWatersheds(corners)
	-- Initially the watershed pointer points downslope one step.      
	for _, q in pairs(corners) do
		q._watershed = q
		if not q._ocean and not q._coast then		  
            q._watershed = q._downslope
		end
	end
	
	-- Follow the downslope pointers to the coast. Limit to 100
	-- iterations although most of the time with self._pointCount=2000 it
	-- only takes 20 iterations because most points are not far from
	-- a coast.  TODO: can run faster by looking at
	-- p.watershed.watershed instead of p.downslope.watershed.
	for i = 1, 100 do
		local changed = false
		for _, q in pairs(corners) do
			if not q._ocean and not q._coast and not q._watershed._coast then
				local r = q._downslope._watershed
				if not r._ocean then
					q._watershed = r
				end
				changed = true
			end
		end
		if not changed then break end
	end
	
	-- How big is each watershed?
	for _, q in pairs(corners) do
		local r = q._watershed
		r._watershed_size = 1 + (r._watershed_size or 0)
	end
end

function OverworldMapGenerator:lookupEdgeFromCorner(q, s)
	for _, edge in pairs(q._protrudes) do
		if edge._v1 == s or edge._v2 == s then
			return edge		
		end
	end
	return nil
end
	
--
--  Create rivers along edges. Pick a random corner point, then
--	move downslope. Mark the edges and corners as rivers.
--
function OverworldMapGenerator:createRivers(corners)      
	-- @TODO how does this number affect things?
	for i = 1, self._riverCount do
		local cn = math.floor(math.random() * #corners) + 1
		local q = corners[cn]
		if not q._ocean and q._elevation >= 0.3 and q._elevation <= 0.9 then
			-- Bias rivers to go west: if q._downslope._point.x <= q._point.x then
			while not q._coast do
				if q == q._downslope then
					break
				end
				local edge = self:lookupEdgeFromCorner(q, q._downslope)
				edge._river = edge._river + 1
				q._river = (q._river or 0) + 1
				q._downslope._river = (q._downslope._river or 0) + 1 -- @TODO: fix double count
				q = q._downslope
			end
		end
	end
end

--
--	Calculate moisture. Freshwater sources spread moisture: rivers
--	and lakes (not oceans). Saltwater sources have moisture but do
--	not spread it (we set it at the end, after propagation).
--
function OverworldMapGenerator:assignCornerMoisture(corners)
	local queue = double_queue:new()
      
	-- Fresh water
	for _, q in pairs(corners) do
		if q._water or q._river > 0 and not q._ocean then
			if q._river > 0 then
				q._moisture = math.min(3.0, (0.2 * q._river))
			else
				q._moisture = 1.0
			end
			queue:pushright(q)
		else
			q._moisture = 0.0
		end		
	end
		
	while queue:count() > 0 do
		local q = queue:popleft()
		for _, r in pairs(q._adjacent) do
			local newMoisture = q._moisture * 0.9
			if newMoisture > r._moisture then
				r._moisture = newMoisture
				queue:pushright(r)
			end
		end
	end
	  
	-- Salt water
	for _, q in pairs(corners) do
		if q._ocean or q._coast then
			q._moisture = 1.0
        end
	end
end

--
-- Change the overall distribution of moisture to be evenly distributed.
--
function OverworldMapGenerator:redistributeMoisture(locations)
	table.sort(locations, function(a,b) return a._moisture < b._moisture end)
	for i = 1, #locations do
        locations[i]._moisture = i / #locations
    end
end

--
--	Polygon moisture is the average of the moisture at corners
--
function OverworldMapGenerator:assignPolygonMoisture(centers)
	for _, p in pairs(centers) do
		local sumMoisture = 0.0
		for _, q in pairs(p._corners) do
			if q._moisture > 1.0 then 
				q._moisture = 1.0
			end
			sumMoisture = sumMoisture + q._moisture
		end
		p._moisture = sumMoisture / table.count(p._corners)
	end
end
	
--
--  Assign a biome type to each polygon. If it has
--  ocean/coast/water, then that's the biome; otherwise it depends
--  on low/high elevation and low/medium/high moisture. This is
--  roughly based on the Whittaker diagram but adapted to fit the
--  needs of the island map generator.
--
--  @TODO If this were a continent generator, latitude might be a 
--	contributor to temperature. Also, wind, evaporation, and rain 
--	shadows might be useful for transporting moisture as humidity. 
--	However, for this generator we keep it simple. 
--
function OverworldMapGenerator:getBiome(p)
	if p._ocean then return 'OCEAN'
	elseif p._water then
		if p._elevation < 0.1 then 
			return 'MARSH'
		elseif p._elevation > 0.8 then 
			return 'ICE'
		else 
			return 'LAKE'
		end
	elseif p._coast then
		return 'BEACH'
	elseif p._elevation > 0.8 then
		if p._moisture > 0.50 then 
			return 'SNOW'
		elseif p._moisture > 0.33 then 
			return 'TUNDRA'
		elseif p._moisture > 0.16 then 
			return 'BARE'
		else 
			return 'SCORCHED'
		end
	elseif p._elevation > 0.6 then
		if p._moisture > 0.66 then 
			return 'TAIGA'
		elseif p._moisture > 0.33 then 
			return 'SHRUBLAND'
		else 
			return 'TEMPERATE_DESERT'
		end
	elseif p._elevation > 0.3 then
		if p._moisture > 0.83 then 
			return 'TEMPERATE_RAIN_FOREST'			
		elseif p._moisture > 0.50 then 
			return 'TEMPERATE_DECIDUOUS_FOREST'
		elseif p._moisture > 0.16 then 
			return 'GRASSLAND'
		else 
			return 'TEMPERATE_DESERT'
		end
	else 
		if p._moisture > 0.66 then 
			return 'TROPICAL_RAIN_FOREST'
		elseif p._moisture > 0.33 then 
			return 'TROPICAL_SEASONAL_FOREST'
		elseif p._moisture > 0.16 then 
			return 'GRASSLAND'
		else 
			return 'SUBTROPICAL_DESERT'
		end			
	end
end
	
--
--  Assigns biomes
--
function OverworldMapGenerator:assignBiomes(centers)
	for _, p in pairs(centers) do	
		p._biome = self:getBiome(p)
	end
end

--
--  Splis the map up into political territories
--	
function OverworldMapGenerator:assignTerritories(centers)
	local queue = double_queue:new()
	
	local tCount = {}
	local maxTerritories = self._pointCount / (self._factionCount*0.33)
	
	-- assign initial territories
	local function isEmpty(q)
		if q._territory then return false end
		for _, r in pairs(q._neighbors) do
			if r._territory then return false end
		end
		return true
	end
	
	for i = 1, self._factionCount do
		local canContinue
		local q
		repeat			
			q = centers[math.floor(math.random() * #centers)]
			canContinue = isEmpty(q)
			if q._ocean then canContinue = false end
		until canContinue
		q._territory = i
		tCount[i] = 1
		queue:pushright(q)
	end
	
	while queue:count() > 0 do
		local q = queue:popleft()
		-- attempt to occupy all neighbouring squares
		if table.count(q._neighbors) > 0 then			
			for _, n in pairs(q._neighbors) do
				if not n._ocean then
					if not n._territory then
						n._territory = q._territory
						tCount[q._territory] = tCount[q._territory] + 1 
						if tCount[q._territory] < maxTerritories or queue:count() == 0 then
							queue:pushright(n)
						end
					end
				end
			end
		end		
	end
end

--
--  Assigns biome groups so that neighbouring types of biomes
--  can be easily referenced as part of one larger biome area
--
function OverworldMapGenerator:assignBiomeGroups(centers)
	local biomeGroup = 0	
	
	local queue = double_queue:new()
	
	local function addNeighbors(q)
		for _, r in pairs(q._neighbors) do
			if r._biome == q._biome and not r._biomeGroup then
				queue:pushright(r)
			end
		end
	end
	
	local biomeIncrement = 0
	for _, q in pairs(centers) do
		biomeIncrement = 0
		if not q._biomeGroup then
			q._biomeGroup = biomeGroup 
			biomeIncrement = 1
			addNeighbors(q)			
		end	
		while queue:count() > 0 do
			local r = queue:popleft()
			r._biomeGroup = biomeGroup
			addNeighbors(r)			
		end				
		biomeGroup = biomeGroup + biomeIncrement
	end	
end

--
--  Contructs and returns the map composed of
--	corners, centers and edges
--
function OverworldMapGenerator:buildMap()
	local profiler = self._profiler
	
	local points, corners, centers, adjacencies
	local gCenters, gCorners, gEdges

	profiler:profile('make perlin noise', function()
		self:makePerlin()
	end) -- profile

	profiler:profile('generate points ', function()	
		points = vd.generatePoints{ count = self._pointCount, seed = self._seed }	
	end) -- profile

	profiler:profile('improve random points ', function()		
		points = self:improveRandomPoints(points)
	end) -- profile		
	
	profiler:profile('build voronoi ', function()			
		corners, centers, adjacencies = vd.voronoi(points)
	end) -- profile

	profiler:profile('build graph', function()		
		gCenters, gCorners, gEdges = vdgraph.buildGraph(points, corners, adjacencies)
	end) -- profile
		
	profiler:profile('improve corners', function()					
		vdgraph.improveCorners(gCorners, gEdges)	
	end) -- profile
	
	profiler:profile('assign corner elevations', function()			
		-- Determine the elevations and water at Voronoi corners
		self:assignCornerElevations(gCorners)
	end) -- profile		

	profiler:profile('assign ocean and coastland', function()			
		-- Determine polygon and corner type: ocean, coast, land.
		self:assignOceanCoastAndLand(gCorners, gCenters)
	end) -- profile		

	profiler:profile('redistribute elevations', function()				
		-- Rescale elevations so that the highest is 1.0, and they're
		-- distributed well. We want lower elevations to be more common
		-- than higher elevations, in proportions approximately matching
		-- concentric rings. That is, the lowest elevation is the
		-- largest ring around the island, and therefore should more
		-- land area than the highest elevation, which is the very
		-- center of a perfectly circular island.
		self:redistributeElevations(self:landPolys(gCorners))
	end) -- profile		

	profiler:profile('assign elevations to non-land corners', function()					
		 -- Assign elevations to non-land corners
		for _, q in pairs(gCorners) do
			if q._ocean or q._coast then
				q._elevation = 0.0
			end                
		end
	end) -- profile		

	profiler:profile('assign polygon elevations', function()						
		-- Polygon elevations are the average of their corners
		self:assignPolygonElevations(gCenters)
	end) -- profile		
	
	profiler:profile('calculate downslopes', function()							
		-- Determine downslope paths.
		self:calculateDownslopes(gCorners)
	end) -- profile		

	profiler:profile('calculate watersheds', function()								
		-- Determine watersheds: for every corner, where does it flow
		-- out into the ocean? 
		self:calculateWatersheds(gCorners)
	end) -- profile		

	profiler:profile('create rivers', function()
		-- Create rivers
		self:createRivers(gCorners)
	end) -- profile		
	
	profiler:profile('determine moisture', function()	
		-- Determine moisture at corners, starting at rivers
		-- and lakes, but not oceans. Then redistribute
		-- moisture to cover the entire range evenly from 0.0
		-- to 1.0. Then assign polygon moisture as the average
		-- of the corner moisture
		self:assignCornerMoisture(gCorners)
		self:redistributeMoisture(self:landPolys(gCorners))
		self:assignPolygonMoisture(gCenters)
	end) -- profile		
	
	profiler:profile('assign biomes', function()
		-- assign biomes
		self:assignBiomes(gCenters)
	end) -- profile		

	profiler:profile('assign biome groups', function()
		-- assign biome groups
		self:assignBiomeGroups(self:landPolys(gCenters))
	end) -- profile		
	
	profiler:profile('assign territories', function()		
		-- assign teritories
		self:assignTerritories(gCenters)
	end) -- profile		
	
	self:logProfiles()	
	
	local generatedMap = OverworldMap{ gCenters, gCorners, gEdges }
	return generatedMap
end

function OverworldMapGenerator:logProfiles()
	log.log(' === PROFILE RESULTS === ')
	for k, v in pairs(self._profiler:profiles()) do
		log.log('----------------------------------------------------------------------')
		log.log(k)
		log.log(table.dump(v))
		log.log('----------------------------------------------------------------------')
	end
end

