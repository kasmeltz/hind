--[[
	vdgraph.lua
	
	Created JUL-30-2012
]]

package.path = package.path .. ';..\\?.lua' 

require 'center'
require 'edge'
require 'corner'
local objects = objects

local log = require 'log'

local pairs, table, math
	= pairs, table, math

module(...)

--
--  Although Lloyd relaxation improves the uniformity of polygon
--	sizes, it doesn't help with the edge lengths. Short edges can
--	be bad for some games, and lead to weird artifacts on
--	rivers. We can easily lengthen short edges by moving the
--  corners, but **we lose the Voronoi property**.  The corners are
--  moved to the average of the polygon centers around them. Short
--  edges become longer. Long edges tend to become shorter. The
 -- polygons tend to be more uniform after this step.
function improveCorners(corners, edges)
	local newCorners = {}
	
	for k, c in pairs(corners) do
		if c._border then
			newCorners[c._id] = c._point
		else
			local p = objects.Point{0,0}
			for r, _ in pairs(c._touches) do
				p.x = p.x + r._point.x
				p.y = p.y + r._point.y
			end
			p.x = p.x / table.count(c._touches)
			p.y = p.y / table.count(c._touches)
			newCorners[c._id] = p
		end
	end
	
	for i = 1, #corners do
		corners[i]._point = newCorners[i]
	end
	
	-- The edge midpoints were computed for the old corners and need
	-- to be recomputed.
	for k, e in pairs(edges) do
		if e._v1 and e._v2  then
			e._midpoint = objects.Point.mid(e._v1._point, e._v2._point, 0.5);
		end
	end
end

--
--  Builds graph objects from the provided 
--  Voronoi relational data created by
--	vd.lua
--
function buildGraph(po, co, aj)	 
    local centers = {}
    local corners = {}
    local edges = {}
	
	local centerBuckets = {}
	local function makeCenter(p)		
		if p.x == math.huge or p.y == math.huge then
			return nil	
		end
		
		if not centerBuckets[p.x] then
			centerBuckets[p.x] = {}
		end
		
		for k, v in pairs(centerBuckets[p.x]) do
			if objects.Point.equals(p, v._point) then
				return v
			end
		end
	
		local c = objects.Center{ #centers + 1, p }
		centers[#centers + 1] = c

		table.insert(centerBuckets[p.x], c)
		
		return c
	end

	local cornerBuckets = {}
	local function makeCorner(p) 
		if p.x == math.huge or p.y == math.huge then 
			return nil
		end
		
		if not cornerBuckets[p.x] then
			cornerBuckets[p.x] = {}
		end	
		
		for k, v in pairs(cornerBuckets[p.x]) do
			if objects.Point.equals(p, v._point) then
				return v
			end
		end
		
		local c = objects.Corner{ #corners + 1, p }
		c._river = 0
		corners[#corners + 1] = c

		table.insert(cornerBuckets[p.x], c)
		
		return c
	end	
	
	for k, a in pairs(aj) do
		local c1 = objects.Point{co.x[a.c1], co.y[a.c1]}
		local c2 = objects.Point{co.x[a.c2], co.y[a.c2]}
		local p1 = objects.Point{po.x[a.p1], po.y[a.p1]}
		local p2 = objects.Point{po.x[a.p2], po.y[a.p2]}
		
		local e = objects.Edge{ #edges + 1 }
		e._river = 0
		e._midpoint = objects.Point.mid(c1, c2)
		
		e._v1 = makeCorner(c1)
		e._v2 = makeCorner(c2)
		e._d1 = makeCenter(p1)
		e._d2 = makeCenter(p2)
		
		edges[#edges + 1] = e	
		
		if e._d1 then e._d1._borders[e] = true end
		if e._d2 then e._d2._borders[e] = true end
		if e._v1 then e._v1._protrudes[e] = true end
		if e._v2 then e._v2._protrudes[e] = true end
		
		if e._d1 and e._d2 then 
			e._d1._neighbors[e._d2] = true
			e._d2._neighbors[e._d1] = true
		end

		if e._v1 and e._v2 then 
			e._v1._adjacent[e._v2] = true
			e._v2._adjacent[e._v1] = true
		end

		if e._d1 then
			if e._v1 then
				e._d1._corners[e._v1] = true
			end
			if e._v2 then
				e._d1._corners[e._v2] = true
			end
		end		
		
		if e._d2 then
			if e._v1 then
				e._d2._corners[e._v1] = true
			end
			if e._v2 then
				e._d2._corners[e._v2] = true
			end
		end		
		
		if e._v1 then
			if e._d1 then
				e._v1._touches[e._d1] = true
			end
			if e._d2 then
				e._v1._touches[e._d2] = true
			end
		end		
		
		if e._v2 then
			if e._d1 then
				e._v2._touches[e._d1] = true
			end
			if e._d2 then
				e._v2._touches[e._d2] = true
			end
		end			
	end
		
	return centers, corners, edges
end