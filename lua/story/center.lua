--[[
	center.lua
	
	Created JUL-30-2012
]]

package.path = package.path .. ';..\\?.lua' 

local Object = (require 'object').Object

module('objects')

Center = Object{ _init = { '_id', '_point' } }

--
--  Center constructor
--
function Center:_clone(values)
	local o = Object._clone(self,values)
	
	o._neighbors = {}
	o._borders = {}
	o._corners = {}

	return o
end