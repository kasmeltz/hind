--[[
	edge.lua
	
	Created JUL-30-2012
]]

package.path = package.path .. ';..\\?.lua' 

local setmetatable = setmetatable

module('edge')

--
-- 	Edge constructor
--
function _M:new(id)
	self.__index = self    
	return setmetatable({_id=id},self)
end