--[[
	point.lua
	
	Created JUL-30-2012
]]

package.path = package.path .. ';..\\?.lua' 

local math, setmetatable
	= math, setmetatable
	
module('point')

local EPS = 1e-12

--
--  point constructor
--
function _M:new(x,y)
	self.__index = self    
	return setmetatable(
		{ 	x = x, y = y, 
			__tostring = function(p) return 'x: ' .. p.x..', y: '..p.y end 
		}, self)
end

--
-- given two points, return a new point between them
--
function _M.mid(a,b)
	return _M:new((a.x + b.x) * 0.5, (a.y + b.y) * 0.5)
end

--
-- given two points, returns a linearly interpolated point between them
--
function _M.interpolate(a, b, f)
	local x = a.x * (1 - f) + b.x * f
	local y = a.y * (1 - f) + b.y * f	
	return _M:new(x, y)
end

--
-- given a point (vector), return the Euclidean norm
--
function _M:norm()
	return math.sqrt( self.x*self.x + self.y*self.y )
end

--
--  Returns true if two points are equal false otherwise
--
function _M.equals(a,b)
	return math.abs(a.x-b.x) < EPS and math.abs(a.y-b.y) < EPS
end

--
--  Subtracts the second point from the first
--
function _M:subtract(p)
	return _M:new(self.x - p.x, self.y - p.y)
end