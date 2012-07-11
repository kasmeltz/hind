--[[
	actor.lua
	
	Created JUN-21-2012
]]

local Object = (require 'object').Object

require 'drawable'
require 'collidable'

local table, pairs, ipairs
	= table, pairs, ipairs
	
module('objects')

Actor = Object{}

--
--  Actor constructor
--
function Actor:_clone(values)
	local o = table.merge(
		Drawable(values),
		table.merge(
			Collidable(values),
			Object._clone(self,values)
		))
			
	o._itemDrawOrder = { 'weapon', 'hands', 'head', 'belt', 
		'torso', 'legs', 'feet', 'body', 'behind' }
  
	o._equipped = {}
	o._inventory = {}
	o._velocity = { 0, 0 }
	o._map = nil
	
	return o
end

--
--  Sets the map that the actor is acting on
--
function Actor:map(m)
	self._map = m
end

--
--  Set or get the velocity 
--
function Actor:velocity(x, y)
	if not x then
		return self._velocity[1], self._velocity[2]
	end
	
	self._velocity[1] = x
	self._velocity[2] = y
end

--
--  Update function
--
function Actor:update(dt)
	self._latestDt = dt
	
	self._lastPosUpdate[1] = (dt * self._velocity[1])
	self._lastPosUpdate[2] = (dt * self._velocity[2])
	
	self._position[1] = self._position[1] + self._lastPosUpdate[1]		
	self._position[2] = self._position[2] + self._lastPosUpdate[2]
	
	-- @TODO do we want to do bounds checking on position
	-- or just let map boundaries handle that by
	-- not letting the character go past a certain point
	local x, y = 800, 600
	local ms = self._map:size()
	if self._position[1] < x then self._position[1] = x end
	if self._position[1] > ms[1] - x then self._position[1] = ms[1] - x end
	if self._position[2] < y then self._position[2] = y end
	if self._position[2] > ms[2] - y then self._position[2] = ms[2] - y end	
	
	-- update the current animation
	self._currentAnimation:update(dt)
	
	-- calculate the bounding boxes
	self:calculateBoundary()
	
	for _, v in pairs(self._equipped) do
		v:update(dt)
	end
end

function Actor:attack()
	-- can only attack once
	if self._isAttacking then
		return 
	end
	
	self._isAttacking = true
	
	self:velocity(0,0)
	
	local currentAnim = self:animation():name()
	local attackAnim = currentAnim:gsub('walk','attack')
	attackAnim = attackAnim:gsub('stand','attack')
	self:animation(attackAnim, true)
	self._currentAnimation.done_cb = function()
		self:animation(currentAnim)
		self._currentAnimation.done_cb = nil			
		self._isAttacking = false
	end
end

--
--  Equips an item
--
function Actor:equipItem(slot, item)
	self._equipped[slot] = item
	item._actor = self
	
	if self._currentAnimation then
		item:animation(self._currentAnimation:name())
	end
end

--
--  Sets or gets the current animation
--
--  Inputs:
--		a - an animation index or nil
--		r - true if the animation should be reset
--
local base_animation = Drawable.animation
function Actor:animation(a, r)	
	local ret = base_animation(self, a, r)
	
	if a then
		-- set the animations for the equipped items
		for _, v in pairs(self._equipped) do
			v:animation(a, r)
		end
	end
	
	return ret
end

--
--  Draw the actor
--
local base_draw = Drawable.draw
function Actor:draw(camera, drawTable)
	base_draw(self, camera, drawTable)
	
	for _, v in ipairs(self._itemDrawOrder) do
		if self._equipped[v] then
			self._equipped[v]:draw(camera, drawTable)
		end
	end
end

--
--  Handle collisions
--
local base_collide = Collidable.collide
function Actor:collide(other)
	base_collide(self,other)
	
	for _, v in pairs(self._equipped) do
		v._position[1] = self._position[1]
		v._position[2] = self._position[2]
		v:calculateBoundary()
	end
end