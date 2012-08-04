--[[
	center.lua
	
	Created JUL-30-2012
]]

local point = require 'point'

package.path = package.path .. ';..\\?.lua' 

local setmetatable, math 
	= setmetatable, math	

module('center')

--
-- 	Center constructor
--
function _M:new(id,p)
	self.__index = self    
	return setmetatable({
		_id=id,_point=p,
		_neighbors={},_borders={},_corners={}},
		self)
end