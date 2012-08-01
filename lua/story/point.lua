--[[
	point.lua
	
	Created JUL-30-2012
]]

package.path = package.path .. ';..\\?.lua' 

local Object = (require 'object').Object

local math
	= math
	
module('objects')

local EPS = 1e-12

Point = Object{ _init = { 'x', 'y' } }

--
--  Center constructor
--
function Point:_clone(values)
	local o = Object._clone(self,values)
	
	o.__tostring = function(p) return 'x: ' .. p.x..', y: '..p.y end
	
	return o
end

--
-- given two points, return a new point between them
--
function Point.mid(a,b)
	return Point{ (a.x + b.x) * 0.5, (a.y + b.y) * 0.5 }
end

--
-- given two points, returns a linearly interpolated point between them
--
function Point.interpolate(a, b, f)
	local x = a.x * (1 - f) + b.x * f
	local y = a.y * (1 - f) + b.y * f	
	return Point{ x, y }
end

--
-- given a point (vector), return the Euclidean norm
--
function Point:norm()
	return math.sqrt( self.x*self.x + self.y*self.y )
end

--
--  Returns true if two points are equal false otherwise
--
function Point.equals(a,b)
	return math.abs(a.x-b.x) < EPS and math.abs(a.y-b.y) < EPS
end

--
--  Subtracts the second point from the first
--
function Point:subtract(p)
	return Point{ self.x - p.x, self.y - p.y }
end