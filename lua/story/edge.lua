--[[
	edge.lua
	
	Created JUL-30-2012
]]

package.path = package.path .. ';..\\?.lua' 

local Object = (require 'object').Object

module('objects')

Edge = Object{ _init = { '_id' } }

--
--  Edge constructor
--
function Edge:_clone(values)
	local o = Object._clone(self,values)
	
	return o
end