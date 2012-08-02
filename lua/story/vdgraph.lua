--[[
	vdgraph.lua
	
	Created JUL-30-2012
]]

package.path = package.path .. ';..\\?.lua' 

local point = require 'point'
local center = require 'center'
local corner = require 'corner'
local edge = require 'edge'

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
			local p = point:new(0,0)
			for _, r in pairs(c._touches) do
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
			e._midpoint = point.mid(e._v1._point, e._v2._point, 0.5);
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
		local cb = centerBuckets[p.x]
		if not cb then
			cb = {}
		else		
			for k, v in pairs(cb) do
				if point.equals(p, v._point) then
					return v
				end
			end
		end
		
		local c = center:new(#centers + 1, p)
		centers[#centers + 1] = c
		cb[#cb+1] = c
		centerBuckets[p.x] = cb
		
		return c
	end

	local cornerBuckets = {}
	local function makeCorner(p)
		local cb = cornerBuckets[p.x]
		if not cb then
			cb = {}
		else		
			for k, v in pairs(cornerBuckets[p.x]) do
				if point.equals(p, v._point) then
					return v
				end
			end	
		end
		
		local c = corner:new(#corners + 1, p)
		corners[#corners + 1] = c
		cb[#cb+1] = c
		cornerBuckets[p.x] = cb
		
		return c
	end	
	
	for k, a in pairs(aj) do
		local c1 = point:new(co.x[a.c1], co.y[a.c1])
		local c2 = point:new(co.x[a.c2], co.y[a.c2])
		local p1 = point:new(po.x[a.p1], po.y[a.p1])
		local p2 = point:new(po.x[a.p2], po.y[a.p2])
		
		local e = edge:new(#edges + 1)
		e._midpoint = point.mid(c1, c2)
		
		local v1 = makeCorner(c1)
		local v2 = makeCorner(c2)
		local d1 = makeCenter(p1)
		local d2 = makeCenter(p2)
		
		d1._borders[e._id] = e 
		d1._corners[v1._id] = v1
		d1._corners[v2._id] = v2
		d1._neighbors[d2._id] = d2
		d2._neighbors[d1._id] = d1		
		d2._borders[e._id] = e 
		d2._corners[v1._id] = v1
		d2._corners[v2._id] = v2	
		v1._protrudes[e._id] = e 
		v1._touches[d1._id] = d1
		v1._touches[d2._id] = d2
		v1._adjacent[v2._id] = v2
		v2._adjacent[v1._id] = v1		
		v2._protrudes[e._id] = e 
		v2._touches[d1._id] = d1
		v2._touches[d2._id] = d2		

		e._v1 = v1
		e._v2 = v2
		e._d1 = d1
		e._d2 = d2
		
		edges[#edges + 1] = e
	end

	return centers, corners, edges
end