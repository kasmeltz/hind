--[[
	corner.lua
	
	Created JUL-30-2012
]]

package.path = package.path .. ';..\\?.lua' 

local Object = (require 'object').Object

module('objects')

Corner = Object{ _init = { '_id', '_point' } }

Corner.MIN_X_VALUE = 0
Corner.MAX_X_VALUE = 1
Corner.MIN_Y_VALUE = 0
Corner.MAX_Y_VALUE = 1
	
--
--  Corner constructor
--
function Corner:_clone(values)
	local o = Object._clone(self,values)
	
	o._border = o._point.x <= Corner.MIN_X_VALUE or o._point.x >= Corner.MAX_X_VALUE
                    or o._point.y <= Corner.MIN_Y_VALUE or o._point.y >= Corner.MAX_Y_VALUE
	o._touches = {}
	o._protrudes = {}
	o._adjacent = {}

	return o
end