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

local NUM_LLOYD_ITERATIONS = 2

-- @todo make this adjustable?
local SIZE = 1
local seed = os.time()

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
	
-- @TODO MAKE THIS ADJUSTABLE
--
--  Returns true if the 
--
local pa, pb, pc = 0.55, 7, 1.5
local perlin = perlin2D(seed, 256, 256, pa, pb, pc)
function islandShape(p)
	local x = math.floor(p.x + 1 * 128) + 1
	local y = math.floor(p.y + 1 * 128) + 1	
	y = math.max(x,256)
	y = math.max(x,256)
	
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

function plot2D(values)
  for r = 1, #values do
    for c = 1, #(values[1]) do
      love.graphics.setColor(128 + 40 * values[r][c], 128 + 40 * values[r][c], 128 + 40 * values[r][c], 255)
      love.graphics.rectangle("fill", (c-1)/(#(values[1]))*love.graphics.getWidth(), (r-1)/(#values)*love.graphics.getHeight(), love.graphics.getWidth()/#(values[1]), love.graphics.getHeight()/#values)
    end
  end
end

function love.load()	
	points = vd.generatePoints{ count = 1000, seed = seed }	
	points = improveRandomPoints(points)
	corners, edges, centers, adjacencies = vd.voronoi(points)
	
	gCenters, gCorners, gEdges = vdgraph.buildGraph(points, corners, adjacencies)
	vdgraph.improveCorners(gCorners, gEdges)
	assignCornerElevations(gCorners)
end

function love.draw()
	local sw, sh = love.graphics.getMode()	
	love.graphics.setBackgroundColor(128,128,128)
	love.graphics.clear()
	
	love.graphics.setColor(0,0,0,255)
	for k, e in pairs(gEdges) do
		if e._v1 and e._v2 then
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
		love.graphics.circle( 'fill', x, y, 2)
	end		
	
	
	for k, c in pairs(gCorners) do
		local x = c._point.x
		local y = c._point.y		
		x = x * sw
		y = y * sh
		
		--[[
		if c._water then		
			love.graphics.setColor(0,0,255,255)
		else
			love.graphics.setColor(0,255,0,255)
		end
		]]
		love.graphics.setColor(c._elevation * 20,0,0,255)
		love.graphics.circle( 'fill', x, y, 2)
	end		
	
	love.graphics.setColor(255,255,255,255)
	love.graphics.print(pa, 0,0)
	love.graphics.print(pb, 0,20)
	love.graphics.print(pc, 0,40)
	--plot2D(perlin)
end

function love.update(dt)

	local updatePerlin = false
	if love.keyboard.isDown('up') then
		pa = pa + 0.01
		updatePerlin = true
	end
	if love.keyboard.isDown('down') then
		pa = pa - 0.01
		updatePerlin = true
	end
	if love.keyboard.isDown('right') then
		pb = pb + 1
		updatePerlin = true
	end
	if love.keyboard.isDown('left') then
		pb = pb - 1
		updatePerlin = true
	end	
	if love.keyboard.isDown('a') then
		pc = pc - 0.01
		updatePerlin = true
	end
	if love.keyboard.isDown('z') then
		pc = pc + 0.01
		updatePerlin = true
	end	

	if updatePerlin then
		perlin = perlin2D(seed, 256, 256, pa, pb, pc)
		assignCornerElevations(gCorners)
	end
end
