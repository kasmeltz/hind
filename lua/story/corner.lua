--[[
	corner.lua
	
	Created JUL-30-2012
]]

package.path = package.path .. ';..\\?.lua' 

local setmetatable = setmetatable

module('corner')

_M.MIN_X_VALUE = 0
_M.MAX_X_VALUE = 1
_M.MIN_Y_VALUE = 0
_M.MAX_Y_VALUE = 1

--
-- 	Corner constructor
--
function _M:new(id,p)
	self.__index = self    
	local o = {_id=id,_point=p}	
	o._border = o._point.x <= _M.MIN_X_VALUE or o._point.x >= _M.MAX_X_VALUE
				or o._point.y <= _M.MIN_Y_VALUE or o._point.y >= _M.MAX_Y_VALUE
	o._touches = {}
	o._protrudes = {}
	o._adjacent = {}	
	o._river = 0
	return setmetatable(o,self)
end