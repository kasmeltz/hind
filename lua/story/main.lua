--[[
	main.lua
	
	Created JUL-30-2012
]]

package.path = package.path .. ';..\\?.lua' 

require 'double_queue'
require 'perlin'
require 'vd'
require 'vdgraph'
require 'log'
require 'table_ext'
require 'point'

-- @TODO put this all into a map generator class
-- @todo make these adjustable?
local NUM_LLOYD_ITERATIONS = 2
local NUM_POINTS = 6000
local LAKE_THRESHOLD = 0.3
local SIZE = 1
local NUM_RIVERS = 1000
local seed = os.time()
local islandFactor, landMass, biomeFeatures = 0.8, 6, 2.5
local showPerlin = 0

local bigFont = love.graphics.newFont(48)
local smallFont = love.graphics.newFont(14)

--
--  Improve the random set of points with Lloyd Relaxation.
--
function improveRandomPoints(points)
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
	for i = 1, NUM_LLOYD_ITERATIONS do
		-- generate voronoi values for the current points
		local corners, _, centers = vd.voronoi(points)
		
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
	
local perlin
function makePerlin()
	perlin = perlin2D(seed, 256, 256, islandFactor, landMass, biomeFeatures)
end
	
--
--  Returns true if the point is on land
--
function islandShape(p)
	local x = math.floor((p.x + 1) * 128)
	local y = math.floor((p.y + 1) * 128)
	x = math.min(x,256)	
	y = math.min(y,256)
	x = math.max(x,1)	
	y = math.max(y,1)
	
	local c = (128 + 40 * perlin[y][x]) / 255	
    return c > (0.3 + 0.3 * p:norm() * p:norm())
end
	
--
-- Determine whether a given point should be on the island or in the water.
--
function inside(p)
	return islandShape(objects.Point{2*(p.x / SIZE - 0.5), 2*(p.y / SIZE - 0.5)})
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
function assignCornerElevations(corners)
	local q = double_queue:new()
	
	for _, c in pairs(corners) do
		c._water = not inside(c._point)
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
		for s, _ in pairs(c._adjacent) do
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
function assignOceanCoastAndLand(corners, centers)
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
		for q, _ in pairs(p._corners) do
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
		p._water = p._ocean or numWater >= table.count(p._corners) * LAKE_THRESHOLD
	end
	
	while queue:count() > 0 do
		local p = queue:popleft()
		for r, _ in pairs(p._neighbors) do
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
        for r, _ in pairs(p._neighbors) do
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
		for p, _ in pairs(q._touches) do
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
--	Create an array of corners that are on land only, for use by
--  algorithms that work only on land.  
--
function landCorners(corners)
	local locations = {}
	for _, c in pairs(corners) do
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
function redistributeElevations(locations)
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
function assignPolygonElevations(centers)
	for _, p in pairs(centers) do
		local sumElevation = 0.0
        for q, _ in pairs(p._corners) do
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
function calculateDownslopes(corners)
	local r
	for _, q in pairs(corners) do
		r = q
		for s, _ in pairs(q._adjacent) do
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
 function calculateWatersheds(corners)
	-- Initially the watershed pointer points downslope one step.      
	for _, q in pairs(corners) do
		q._watershed = q
		if not q._ocean and not q._coast then		  
            q._watershed = q._downslope
		end
	end
	
	-- Follow the downslope pointers to the coast. Limit to 100
	-- iterations although most of the time with NUM_POINTS=2000 it
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

function lookupEdgeFromCorner(q, s)
	for edge, _ in pairs(q._protrudes) do
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
function createRivers(corners)      
	-- @TODO how does this number affect things?
	for i = 1, NUM_RIVERS do
		local cn = math.floor(math.random() * #corners) + 1
		local q = corners[cn]
		if not q._ocean and q._elevation >= 0.3 and q._elevation <= 0.9 then
			-- Bias rivers to go west: if q._downslope._point.x <= q._point.x then
			while not q._coast do
				if q == q._downslope then
					break
				end
				local edge = lookupEdgeFromCorner(q, q._downslope)
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
function assignCornerMoisture(corners)
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
		for r, _ in pairs(q._adjacent) do
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
function redistributeMoisture(locations)
	table.sort(locations, function(a,b) return a._moisture < b._moisture end)
	for i = 1, #locations do
        locations[i]._moisture = i / #locations
    end
end

--
--	Polygon moisture is the average of the moisture at corners
--
function assignPolygonMoisture(centers)
	for _, p in pairs(centers) do
		local sumMoisture = 0.0
		for q, _ in pairs(p._corners) do
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
function getBiome(p)
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
	
function assignBiomes(centers)
	for _, p in pairs(centers) do	
		p._biome = getBiome(p)
	end
end
	
function buildMap()
	makePerlin()

	local points = vd.generatePoints{ count = NUM_POINTS, seed = seed }	
	local points = improveRandomPoints(points)
	local corners, edges, centers, adjacencies = vd.voronoi(points)
	
	gCenters, gCorners, gEdges = vdgraph.buildGraph(points, corners, adjacencies)
	vdgraph.improveCorners(gCorners, gEdges)	
	
	-- Determine the elevations and water at Voronoi corners
	assignCornerElevations(gCorners)

	-- Determine polygon and corner type: ocean, coast, land.
	assignOceanCoastAndLand(gCorners, gCenters)

    -- Rescale elevations so that the highest is 1.0, and they're
	-- distributed well. We want lower elevations to be more common
	-- than higher elevations, in proportions approximately matching
	-- concentric rings. That is, the lowest elevation is the
	-- largest ring around the island, and therefore should more
	-- land area than the highest elevation, which is the very
	-- center of a perfectly circular island.
	redistributeElevations(landCorners(gCorners))
	
	 -- Assign elevations to non-land corners
	for _, q in pairs(gCorners) do
		if q._ocean or q._coast then
			q._elevation = 0.0
		end                
	end
	
	-- Polygon elevations are the average of their corners
	assignPolygonElevations(gCenters)
	
	-- Determine downslope paths.
	calculateDownslopes(gCorners)
	
	-- Determine watersheds: for every corner, where does it flow
    -- out into the ocean? 
	calculateWatersheds(gCorners)
	
	-- Create rivers
	createRivers(gCorners)
	
	-- Determine moisture at corners, starting at rivers
	-- and lakes, but not oceans. Then redistribute
	-- moisture to cover the entire range evenly from 0.0
	-- to 1.0. Then assign polygon moisture as the average
	-- of the corner moisture
	assignCornerMoisture(gCorners)
	redistributeMoisture(landCorners(gCorners))
	assignPolygonMoisture(gCenters)
	
	-- assign biomes
	assignBiomes(gCenters)
end

function love.load()	
	buildMap()
end

function plot2D(values)
  for r = 1, #values do
    for c = 1, #(values[1]) do
      love.graphics.setColor(128 + 40 * values[r][c], 128 + 40 * values[r][c], 128 + 40 * values[r][c], 255)
      love.graphics.rectangle("fill", (c-1)/(#(values[1]))*love.graphics.getWidth(), (r-1)/(#values)*love.graphics.getHeight(), love.graphics.getWidth()/#(values[1]), love.graphics.getHeight()/#values)
    end
  end
end

local drawMode = 'biomes'

--[[
			
			
			
			return 'SUBTROPICAL_DESERT'
]]

local biomeColors = 
	{ 
		OCEAN = { 0, 0, 100 },
		LAKE = { 0, 0, 200 },
		MARSH = { 20, 30, 70 },
		ICE = { 170, 170, 255 },
		BEACH = { 100, 100, 50 },
		SNOW = { 220, 220, 255 },
		TUNDRA = { 128, 128, 128 },
		BARE = { 64, 64, 64 },
		SCORCHED = { 80, 80, 40 },
		TAIGA = { 0, 40, 0 },
		SHRUBLAND = { 100, 100, 20 },
		GRASSLAND = { 0, 130, 0 },
		TEMPERATE_DESERT = { 130, 130, 0},
		TEMPERATE_DECIDUOUS_FOREST = { 30, 80, 30} ,
		TEMPERATE_RAIN_FOREST = { 0, 80, 80 },		
		TROPICAL_RAIN_FOREST = { 50, 200, 50 },
		TROPICAL_SEASONAL_FOREST = { 140, 160, 80 },
		SUBTROPICAL_DESERT = { 170, 170, 0 }
	}
	
function drawBiomes()
	local sw, sh = love.graphics.getMode()	
	love.graphics.setBackgroundColor(128,128,128)
	love.graphics.clear()

	for _, ce in pairs(gCenters) do
		local col = biomeColors[ce._biome]
		if col then
			love.graphics.setColor(col[1], col[2], col[3], 255)
		else
			love.graphics.setColor(0,0,0,255)
		end
	
		local verts = {}
		for ed, _ in pairs(ce._borders) do
			if ed._v1 and ed._v2 then
				local x1 = ed._v1._point.x
				local y1 = ed._v1._point.y
				local x2 = ed._v2._point.x
				local y2 = ed._v2._point.y
				verts[#verts+1] = x1 * sw
				verts[#verts+1] = y1 * sh
				verts[#verts+1] = x2 * sw
				verts[#verts+1] = y2 * sh
			end
		end
		
		if #verts >= 6 then
			love.graphics.polygon('fill', verts)
		end
	end
	
	for _, ed in pairs(gEdges) do
		if ed._v1 and ed._v2 then		
			if ed._river > 0 then
				love.graphics.setColor(0, 0, 255, 255)		
				local x1 = ed._v1._point.x
				local y1 = ed._v1._point.y
				local x2 = ed._v2._point.x
				local y2 = ed._v2._point.y
				x1 = x1 * sw
				y1 = y1 * sh
				x2 = x2 * sw
				y2 = y2 * sh
				love.graphics.line(x1,y1,x2,y2)					
			end			
		end		
	end
end

function drawElevation()
	local sw, sh = love.graphics.getMode()	
	love.graphics.setBackgroundColor(128,128,128)
	love.graphics.clear()
	
	love.graphics.setColor(0,0,0,255)
	for k, e in pairs(gEdges) do
		if e._v1 and e._v2 then		
			local elev = ((e._v1._elevation) + (e._v2._elevation)) / 2			
			local r, g, b = 0, 255, 0
		
			if e._river > 0 then
				r = 0 g = 0 b = 255
				elev = 1
			end
			if (e._v1 and e._v1._ocean) or (e._v2 and e._v2._ocean) then
				r = 0 g = 0 b = 255
				elev = 1
			end
			if (e._v1 and e._v1._coast) and (e._v2 and e._v2._coast) then
				r = 255 g = 255 b = 0
				elev = 1
			end
			
			love.graphics.setColor(r * elev, g * elev, b * elev, 255)
		
			local x1 = e._v1._point.x
			local y1 = e._v1._point.y
			local x2 = e._v2._point.x
			local y2 = e._v2._point.y

			x1 = x1 * sw
			y1 = y1 * sh
			x2 = x2 * sw
			y2 = y2 * sh
			love.graphics.line(x1,y1,x2,y2)					
		end			
	end
	
	for k, c in pairs(gCenters) do
		local x = c._point.x
		local y = c._point.y		
		x = x * sw
		y = y * sh
		
		local r, g, b 
		local elev = c._elevation
		if c._ocean then		
			r = 0 g = 0 b = 255
		elseif c._coast then
			r = 255 g = 255 b = 0
		else
			r = 0 g = 255 b = 0
		end		
		love.graphics.setColor(r * elev,g * elev,b * elev,255)
		love.graphics.circle( 'fill', x, y, 2)
	end		
	
	for k, c in pairs(gCorners) do
		local x = c._point.x
		local y = c._point.y		
		x = x * sw
		y = y * sh
		
		local r, g, b 
		local elev = c._elevation
		if c._ocean then		
			r = 0 g = 0 b = 255
			elev = 1
		elseif c._coast then
			r = 255 g = 255 b = 0
			elev = 1
		else
			r = 0 g = 255 b = 0
		end		
		love.graphics.setColor(r * elev,g * elev,b * elev,255)
		love.graphics.circle( 'fill', x, y, 2)
	end	
end

function drawMoisture()
	local sw, sh = love.graphics.getMode()	
	love.graphics.setBackgroundColor(128,128,128)
	love.graphics.clear()
	
	love.graphics.setColor(0,0,0,255)
	for k, e in pairs(gEdges) do
		if e._v1 and e._v2 then		
			local elev = ((e._v1._moisture) + (e._v2._moisture)) / 2			
			local r, g, b = 0, 255, 0
		
			if e._river > 0 then
				r = 0 g = 0 b = 255
			end
			if (e._v1 and e._v1._ocean) or (e._v2 and e._v2._ocean) then
				r = 0 g = 0 b = 255
			end
			if (e._v1 and e._v1._coast) and (e._v2 and e._v2._coast) then
				r = 255 g = 255 b = 0
			end
			
			love.graphics.setColor(r * elev, g * elev, b * elev, 255)
		
			local x1 = e._v1._point.x
			local y1 = e._v1._point.y
			local x2 = e._v2._point.x
			local y2 = e._v2._point.y

			x1 = x1 * sw
			y1 = y1 * sh
			x2 = x2 * sw
			y2 = y2 * sh
			love.graphics.line(x1,y1,x2,y2)					
		end			
	end
	
	for k, c in pairs(gCenters) do
		local x = c._point.x
		local y = c._point.y		
		x = x * sw
		y = y * sh
		
		local r, g, b 
		local elev = c._moisture
		if c._ocean then		
			r = 0 g = 0 b = 255
		elseif c._coast then
			r = 255 g = 255 b = 0
		else
			r = 0 g = 255 b = 0
		end		
		love.graphics.setColor(r * elev,g * elev,b * elev,255)
		love.graphics.circle( 'fill', x, y, 2)
	end		
	
	for k, c in pairs(gCorners) do
		local x = c._point.x
		local y = c._point.y		
		x = x * sw
		y = y * sh
		
		local r, g, b 
		local elev = c._moisture
		if c._ocean then		
			r = 0 g = 0 b = 255
		elseif c._coast then
			r = 255 g = 255 b = 0
		else
			r = 0 g = 255 b = 0
		end		
		love.graphics.setColor(r * elev,g * elev,b * elev,255)
		love.graphics.circle( 'fill', x, y, 2)
	end	
end


function love.draw()
	if showPerlin == 1 then 
		plot2D(perlin)
		return
	end
	
	if drawMode == 'biomes' then
		drawBiomes()
	elseif drawMode == 'elevation' then
		drawElevation()
	elseif drawMode == 'moisture' then
		drawMoisture()
	end
	
	love.graphics.setColor(255,255,0,255)
	
	love.graphics.setFont(bigFont)
	love.graphics.print(drawMode, 10, 10)
	
	love.graphics.setFont(smallFont)	
	love.graphics.print('1: biomes 2: elevation 3: moisture', 10, 90)
	love.graphics.print('noise island factor (approx.) (UP-DOWN): ' .. islandFactor, 10,110)
	love.graphics.print('noise land mass (approx.) (LEFT-RIGHT): ' .. landMass, 10,130)	
	love.graphics.print('noise biome features (approx.) (A-Z): ' .. biomeFeatures, 10,150)	
	love.graphics.print('polygons (S-X): ' .. NUM_POINTS, 10, 170)
	love.graphics.print('rivers (D-C): ' .. NUM_RIVERS, 10, 190)
	love.graphics.print('land mass (F-V): ' .. LAKE_THRESHOLD, 10, 210)
	love.graphics.print('seed (G-B): ' .. seed, 10, 230)
	love.graphics.print('rebuild map (M)', 10, 250)
end

function love.update(dt)

	local updatePerlin = false
	if love.keyboard.isDown('up') then
		islandFactor = islandFactor + 0.05
	end
	if love.keyboard.isDown('down') then
		islandFactor = islandFactor - 0.05
	end
	
	if islandFactor < 0 then islandFactor = 0 end	
	if islandFactor > 2 then islandFactor = 2 end
	
	if love.keyboard.isDown('a') then
		biomeFeatures = biomeFeatures + 0.05
	end
	if love.keyboard.isDown('z') then
		biomeFeatures = biomeFeatures - 0.05
	end	
	
	if biomeFeatures < 0 then biomeFeatures = 0 end	
	if biomeFeatures > 5 then biomeFeatures = 5 end
	
	if love.keyboard.isDown('s') then
		NUM_POINTS = NUM_POINTS + 100
	end
	if love.keyboard.isDown('x') then
		NUM_POINTS = NUM_POINTS - 100
	end	
	
	if NUM_POINTS < 100 then NUM_POINTS = 100 end	
	if NUM_POINTS > 6000 then NUM_POINTS = 6000 end
	
	if love.keyboard.isDown('d') then
		NUM_RIVERS = NUM_RIVERS + 50
	end
	if love.keyboard.isDown('c') then
		NUM_RIVERS = NUM_RIVERS - 50
	end	
	
	if NUM_RIVERS < 50 then NUM_RIVERS = 50 end	
	if NUM_RIVERS > 6000 then NUM_RIVERS = 6000 end
	
	if love.keyboard.isDown('f') then
		LAKE_THRESHOLD = LAKE_THRESHOLD + 0.005
	end
	if love.keyboard.isDown('v') then
		LAKE_THRESHOLD = LAKE_THRESHOLD - 0.005
	end	
	
	if LAKE_THRESHOLD < 0 then LAKE_THRESHOLD = 0 end	
	if LAKE_THRESHOLD > 1 then LAKE_THRESHOLD = 1 end
	
	if love.keyboard.isDown('g') then
		seed = seed + 162837
	end
	if love.keyboard.isDown('b') then
		seed = seed - 162837
	end	
end

function love.keyreleased(key)
	if key == 'w' then
		showPerlin = 1 - showPerlin
	end

	if key == 'right' then
		landMass = landMass + 1
	end
	if key == 'left' then
		landMass = landMass - 1
	end	
	if landMass < 1 then landMass = 1 end
	if landMass > 10 then landMass = 10 end
	
	if key == 'm' then
		buildMap()
	end		
	if key == '1' then
		drawMode = 'biomes'
	end
	if key == '2' then
		drawMode = 'elevation'
	end
	if key == '3' then
		drawMode = 'moisture'
	end
	
end
