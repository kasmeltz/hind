--[[
	overworld_map.lua
	
	Created AUG-02-2012
]]

local Object = (require 'object').Object

module('objects')

OverworldMap = Object{ _init = { '_centers', '_corners', '_edges' } }
		
--
--  OverworldMap constructor
--
function OverworldMap:_clone(values)
	local o = Object._clone(self,values)
			
	return o
end