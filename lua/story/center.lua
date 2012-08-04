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
		_minPoint = point:new(2,2),
		_maxPoint = point:new(-2,-2),
		_neighbors={},_borders={},_corners={}},
		self)
end