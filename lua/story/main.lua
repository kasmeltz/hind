--[[
	main.lua
	
	Created JUL-30-2012
]]

package.path = package.path .. ';..\\?.lua' 

require 'log'
require 'point'
require 'overworld_map_generator'
require 'map_rasterizer'

local showPerlin = 0
local NUM_LLOYD = 2
local NUM_POINTS = 10000
local islandFactor = 0.8
local landMass = 6
local biomeFeatures = 2.5
local NUM_FACTIONS = 6
local NUM_RIVERS = 1000
local LAKE_THRESHOLD = 0.3
local NOISY_LINE_TRADEOFF = 0.5
local seed = os.time()
local rasterX = 2048
local rasterY = 2048

local bigFont = love.graphics.newFont(48)
local medFont = love.graphics.newFont(24)
local smallFont = love.graphics.newFont(14)

--
--	Helper function: build a single noisy line in a quadrilateral A-B-C-D,
--	and store the output points in a table
--
function buildNoisyLineSegments(A, B, C, D, minLength)
      local points = {}

      local function subdivide(A, B, C, D)
        if A:subtract(C):norm() < minLength or B:subtract(D):norm() < minLength then
			return
		end

        -- Subdivide the quadrilateral
        local p = math.random() * 0.6 + 0.2 
        local q = math.random() * 0.6 + 0.2

        -- Midpoints
        local E = point.interpolate(A,D,p)
		local F = point.interpolate(B,C,p)
		local G = point.interpolate(A,B,q)
		local I = point.interpolate(D,C,q)
        
        -- Central point
        local H = point.interpolate(E,F,q)
        
        -- Divide the quad into subquads, but meet at H
        local s = 1.0 - math.random() * 0.8 - 0.4
        local t = 1.0 - math.random() * 0.8 - 0.4

        subdivide(A, point.interpolate(G, B, s), H, point.interpolate(E, D, t))
        points[#points+1] = H
        subdivide(H, point.interpolate(F, C, s), C, point.interpolate(I, D, t))
      end

      points[#points + 1] = A
      subdivide(A, B, C, D)
      points[#points + 1] = C
      
	  return points
end
  
--
--  Build noisy line paths for each of the Voronoi edges. There are
--  two noisy line paths for each edge, each covering half the
--  distance: path0 is from v0 to the midpoint and path1 is from v1
--  to the midpoint. When drawing the polygons, one or the other
--  must be drawn in reverse order.
--
function buildNoisyEdges(centers)
	local path1 = {}
	local path2 = {}
	
	for _, p in pairs(centers) do
		for _, edge in pairs(p._borders) do
			if edge._d1 and edge._d2 and edge._v1 and edge._v2 and not path1[edge._id] then
				local f = NOISY_LINE_TRADEOFF
				local t = point.interpolate(edge._v1._point, edge._d1._point, f)
				local q = point.interpolate(edge._v1._point, edge._d2._point, f)
				local r = point.interpolate(edge._v2._point, edge._d1._point, f)
				local s = point.interpolate(edge._v2._point, edge._d2._point, f)
				
				if t.x ~= math.huge and t.y ~= math.huge and
					q.x ~= math.huge and q.y ~= math.huge and
					r.x ~= math.huge and s.y ~= math.huge and
					s.x ~= math.huge and s.y ~= math.huge then

					local minLength = 100 / self._pointCount
					if edge._d1._biome ~= edge._d2._biome then
						minLength = 30 / self._pointCount
					end
					if edge._d1._ocean and edge._d2._ocean then
						minLength = 1000 / self._pointCount
					end
					if edge._d1._coast or edge._d2._coast then
						minLength = 10 / self._pointCount
					end
					if edge._river then --[[or lava.lava[edge.index])]]
						minLength = 10 / self._pointCount
					end

					path1[edge._id] = buildNoisyLineSegments(edge._v1._point, t, edge._midpoint, q, minLength)
					path2[edge._id] = buildNoisyLineSegments(edge._v2._point, s, edge._midpoint, r, minLength)
				end
			end
		end
	end
	
	return path1, path2
end

local drawMode = 'biomes'
function drawMap()
	if drawMode == 'biomes' then
		drawBiomes(mapCanvas)
	elseif drawMode == 'elevation' then
		drawElevation(mapCanvas)
	elseif drawMode == 'moisture' then
		drawMoisture(mapCanvas)
	elseif drawMode == 'territories' then
		drawTerritories(mapCanvas)
	end
end

function buildMap()
	mapGenerator:configure{ lloydCount = NUM_LLOYD, pointCount = NUM_POINTS, 
		lakeThreshold = LAKE_THRESHOLD, size = 1, riverCount = NUM_RIVERS, 
		factionCount = NUM_FACTIONS, seed = seed, islandFactor = islandFactor, 
		landMass = landMass, biomeFeatures = biomeFeatures}
	map = mapGenerator:buildMap()
end

function love.load()	
	mapCanvas = love.graphics.newCanvas()	
	mapGenerator = objects.OverworldMapGenerator{}	
	buildMap()
	mapRasterizer = objects.MapRasterizer{ map }
	mapRasterizer:initialize(point:new(0,0), point:new(1,1), point:new(4096,4096))
	drawMap()
end

--
--  Draws noisy edges
--
function getNoisyEdges(id)
	local p1 = {}
	local p2 = {}
		
	local segs = nEdges1[id]
	if segs then
		for _, v in ipairs(segs) do
			p1[#p1+1] = v
		end
	end
	
	local segs = nEdges2[id]
	if segs then
		for _, v in ipairs(segs) do
			p2[#p2+1] = v
		end	
	end
	
	return p1, p2
end

function plot2D(values)
  for r = 1, #values do
    for c = 1, #(values[1]) do
      love.graphics.setColor(128 + 40 * values[r][c], 128 + 40 * values[r][c], 128 + 40 * values[r][c], 255)
      love.graphics.rectangle("fill", 
		(c-1)/(#(values[1]))*love.graphics.getWidth(), 
		(r-1)/(#values)*love.graphics.getHeight(), 
		love.graphics.getWidth()/#(values[1]), 
		love.graphics.getHeight()/#values)
    end
  end
end

local biomeColors = 
	{ 
		OCEAN = { 0, 20, 60 },
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
	
local biomeNumbers =
	{
		{ 0, 20, 60 },
		{ 0, 0, 200 },
		{ 20, 30, 70 },
		{ 170, 170, 255 },
		{ 100, 100, 50 },
		{ 220, 220, 255 },
		{ 128, 128, 128 },
		{ 64, 64, 64 },
		{ 80, 80, 40 },
		{ 0, 40, 0 },
		{ 100, 100, 20 },
		{ 0, 130, 0 },
		{ 130, 130, 0},
		{ 30, 80, 30} ,
		{ 0, 80, 80 },		
		{ 50, 200, 50 },
		{ 140, 160, 80 },
		{ 170, 170, 0 }
	}
	
function drawBiomes(cnv)
	local sw, sh 
	
	if cnv then
		sw, sh = cnv:getWidth(), cnv:getHeight()
		love.graphics.setCanvas(cnv)
	else
		sw, sh = love.graphics.getMode()	
		love.graphics.setCanvas()
	end
	love.graphics.setBackgroundColor(128,128,128)
	love.graphics.clear()

	for _, ce in pairs(map._centers) do
		local col = biomeColors[ce._biome]
		if col then
			love.graphics.setColor(col[1], col[2], col[3], 255)
		else
			love.graphics.setColor(0,0,0,255)
		end
	
		local verts = {}
		
		--[[
		local function addNoisyVerts(ps)
			for i = 1, #ps - 1 do
				verts[#verts+1] = ps[i].x * sw
				verts[#verts+1] = ps[i].y * sh
				verts[#verts+1] = ps[i+1].x * sw
				verts[#verts+1] = ps[i+1].y * sh
			end		
		end
		]]
		
		for i = 1, #ce._corners do	
			local ind = (i%#ce._corners) + 1
			
			local co1 = ce._corners[i]
			local co2 = ce._corners[ind]
			
		--for _, ed in pairs(ce._borders) do			
			--if ed._v1 and ed._v2 then
				--[[
				local p1, p2 = getNoisyEdges(ed._id)
				addNoisyVerts(p1)
				addNoisyVerts(p2)
				]]				
				--[[
				local x1 = ed._v1._point.x
				local y1 = ed._v1._point.y
				local x2 = ed._v2._point.x
				local y2 = ed._v2._point.y
				]]
				local x1 = co1._point.x
				local y1 = co1._point.y
				local x2 = co2._point.x
				local y2 = co2._point.y
				
				verts[#verts+1] = x1 * sw
				verts[#verts+1] = y1 * sh
				verts[#verts+1] = x2 * sw
				verts[#verts+1] = y2 * sh
			--end
		end	
		
		if #verts >= 6 then
			love.graphics.polygon('fill', verts)
		end
		
		if mapRasterizer._cellsToRaster[ce._id] then
			love.graphics.setColor(255,0,255,255)
			love.graphics.circle('fill', ce._point.x * sw, ce._point.y * sh, 1)
		end
	end
	
	--[[
	local function drawRiverEdge(ps)
		for i = 1, #ps - 1 do
			local x1 = ps[i].x * sw
			local y1 = ps[i].y * sh
			local x2 = ps[i+1].x * sw
			local y2 = ps[i+1].y * sh
			love.graphics.line(x1,y1,x2,y2)
		end
	end
	]]
	
	for _, ed in pairs(map._edges) do
		if ed._d1 and ed._d2 and (not ed._d1._water or not ed._d2._water) then
			if ed._v1 and ed._v2 then		
				if ed._river > 0 then
					love.graphics.setColor(0, 0, 255, 255)	
					--[[
					local p1, p2 = getNoisyEdges(ed._id)
					drawRiverEdge(p1)
					drawRiverEdge(p2)
					]]					
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

	for _, ed in pairs(map._edges) do
		if ed._d1 and ed._d2 and ed._v1 and ed._v2 then		
			if (ed._d1._biomeGroup or ed._d2._biomeGroup) and 
				ed._d1._biomeGroup ~= ed._d2._biomeGroup then
				love.graphics.setColor(0, 0, 0, 255)		
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
	
	love.graphics.setCanvas()
end

local territoryColors = 
	{
		{ 255, 0 ,0 },
		{ 255, 255 ,0 },
		{ 0, 255 ,255 },
		{ 0, 0, 255 },
		{ 255, 0 ,255 },
		{ 0, 255 ,0 },
		{ 255, 255 ,255 },
		{ 128, 128 ,128 },
		{ 128, 128 ,0 },
		{ 0, 128 ,128 }		
	}
	
local territoryNames = 
	{
		'Smeltzville',
		'Virginia',
		'Kleinrich',
		'Apolonia',
		'CKPP',
		'Gulgantua',
		'Fry',
		'Monarchsland',
		'Polologogo',
		'Westerlund'
	}
function drawTerritories(cnv)
	local sw, sh 
	
	if cnv then
		sw, sh = cnv:getWidth(), cnv:getHeight()
		love.graphics.setCanvas(cnv)
	else
		sw, sh = love.graphics.getMode()	
		love.graphics.setCanvas()
	end	
	love.graphics.setBackgroundColor(128,128,128)
	love.graphics.clear()
	
	local tPoints = {}
	local tCounts = {}
	for i = 1, NUM_FACTIONS do
		tPoints[i] = point:new(0,0)
		tCounts[i] = 0
	end

	for _, ce in pairs(map._centers) do
		local col
		local ter = ce._territory		
		if ter then
			col = territoryColors[ce._territory]
			love.graphics.setColor(col[1], col[2], col[3], 180)
			tPoints[ter].x = tPoints[ter].x + ce._point.x
			tPoints[ter].y = tPoints[ter].y + ce._point.y
			tCounts[ter] = tCounts[ter] + 1
		else
			love.graphics.setColor(64,64,64,64)
		end
							
		local verts = {}
		for _, ed in pairs(ce._borders) do
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
	
	for _, ed in pairs(map._edges) do
		if ed._d1 and ed._d2 and ed._v1 and ed._v2 then		
			if ed._d1._territory ~= ed._d2._territory then
				love.graphics.setColor(0, 0, 0, 255)		
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
	
	love.graphics.setFont(medFont)	
	for i = 1, NUM_FACTIONS do
		tPoints[i].x = tPoints[i].x / tCounts[i]
		tPoints[i].y = tPoints[i].y / tCounts[i]
		
		local txt = territoryNames[i]
		local x = tPoints[i].x * sw - (medFont:getWidth(txt) / 2)
		local y = tPoints[i].y * sh - (medFont:getHeight(txt) / 2)				
		love.graphics.print(txt,x,y)
	end
	
	love.graphics.setCanvas()
end

function drawElevation(cnv)
	local sw, sh 
	
	if cnv then
		sw, sh = cnv:getWidth(), cnv:getHeight()
		love.graphics.setCanvas(cnv)
	else
		sw, sh = love.graphics.getMode()	
		love.graphics.setCanvas()
	end	
	love.graphics.setBackgroundColor(128,128,128)
	love.graphics.clear()
	
	love.graphics.setColor(0,0,0,255)
	for k, e in pairs(map._edges) do
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
	
	for k, c in pairs(map._centers) do
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
	
	for _, c in pairs(map._corners) do
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
	love.graphics.setCanvas()	
end

function drawMoisture(cnv)
	local sw, sh 
	
	if cnv then
		sw, sh = cnv:getWidth(), cnv:getHeight()
		love.graphics.setCanvas(cnv)
	else
		sw, sh = love.graphics.getMode()	
		love.graphics.setCanvas()
	end	
	love.graphics.setBackgroundColor(128,128,128)
	love.graphics.clear()
	
	love.graphics.setColor(0,0,0,255)
	for k, e in pairs(map._edges) do
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
	
	for k, c in pairs(map._centers) do
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
	
	for _, c in pairs(map._corners) do
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
	love.graphics.setCanvas()	
end


function love.draw()
	if showPerlin == 1 then 
		plot2D(mapGenerator._perlin)
		return
	end
	
	love.graphics.draw(mapCanvas,0,0)
	
	love.graphics.setColor(255,255,255,200)	
	love.graphics.setFont(bigFont)
	love.graphics.print(drawMode, 10, 10)
	
	love.graphics.setFont(smallFont)	
	love.graphics.print('1: biomes 2: elevation 3: moisture 4: territories', 10, 90)
	love.graphics.print('noise island factor (approx.) (UP-DOWN): ' .. islandFactor, 10,110)
	love.graphics.print('noise land mass (approx.) (LEFT-RIGHT): ' .. landMass, 10,130)	
	love.graphics.print('noise biome features (approx.) (A-Z): ' .. biomeFeatures, 10,150)	
	love.graphics.print('polygons (S-X): ' .. NUM_POINTS, 10, 170)
	love.graphics.print('rivers (D-C): ' .. NUM_RIVERS, 10, 190)
	love.graphics.print('land mass (F-V): ' .. LAKE_THRESHOLD, 10, 210)
	love.graphics.print('seed (G-B): ' .. seed, 10, 230)
	love.graphics.print('factions (H-N): ' .. NUM_FACTIONS, 10, 250)
	love.graphics.print('rebuild map (O)', 10, 270)
	
	if mapRasterizer._area then
		local sx = 900
		local sy = 50
		for y = 1, mapRasterizer._area.y do
			sy = sy + 8
			sx = 900
			for x = 1, mapRasterizer._area.x do
				local v = mapRasterizer._tiles[y][x]
				local c = biomeNumbers[v+1]
				love.graphics.setColor(c[1],c[2],c[3],255)
				love.graphics.rectangle('fill', sx, sy, 8, 8)
				sx = sx + 8
			end
		end
	end	
	
	love.graphics.setColor(255,255,255,255)
end

function love.update(dt)
	mapRasterizer:rasterize(point:new(rasterX,rasterY), point:new(8,8))
		
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
	if NUM_POINTS > 60000 then NUM_POINTS = 60000 end
	
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
	if key == 'u' then
		rasterY = rasterY - 8
	end
	if key == 'j' then
		rasterY = rasterY + 8
	end
	if key == 'h' then
		rasterX = rasterX - 8
	end
	if key == 'k' then
		rasterX = rasterX + 8
	end

	
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

	if key == 'h' then
		NUM_FACTIONS = NUM_FACTIONS + 1
	end
	if key == 'n' then
		NUM_FACTIONS = NUM_FACTIONS - 1
	end	
	if NUM_FACTIONS < 1 then NUM_FACTIONS = 1 end
	if NUM_FACTIONS > 10 then NUM_FACTIONS = 10 end	
	
	if key == 'o' then
		buildMap()
		drawMap()
	end		
	if key == '1' then
		drawMode = 'biomes'
		drawMap()
	end
	if key == '2' then
		drawMode = 'elevation'
		drawMap()
	end
	if key == '3' then
		drawMode = 'moisture'
		drawMap()		
	end
	if key == '4' then
		drawMode = 'territories'
		drawMap()
	end			

	end