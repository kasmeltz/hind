--[[
	floating_text.lua
	
	Created JUL-12-2012
]]

local Object = (require 'object').Object

require 'drawable'

local table, math 
	= table, math
	
module('objects')

FloatingText = Object{ _init = { 
		'_text', '_font', '_color', 
		'_position', '_velocity', '_timeToLive', 
		'_screenSpace' }}

--
--  FloatingTexts support the following Events:
--		on_expired - will be called when the floating alive time has expired
--

--
--  FloatingText constructor
--
function FloatingText:_clone(values)
	local o = table.merge(Drawable(values), Object._clone(self,values))
		
	o._currentTime = 0
	o._drawTable = { true, true, true, true, true }
	
	return o
end

--
--  Update function
--
function FloatingText:update(dt)
	self._position[1] = self._position[1] + (dt * self._velocity[1])
	self._position[2] = self._position[2] + (dt * self._velocity[2])

    self._currentTime = self._currentTime + dt
	
	if self._currentTime >= self._timeToLive then
		if self.on_expired then
			self:on_expired()
		end
	end
end

--
--  Draw the drawable
--
function FloatingText:draw(camera, drawTable)
	local cw, cv, zoomX, zoomY, cwzx, cwzy =
		drawTable.cw, drawTable.cv, 
		drawTable.zoomX, drawTable.zoomY,
		drawTable.cwzx, drawTable.cwzy		

	if not self._screenSpace then
		self._screenPos[1] = math.floor((self._position[1] * zoomX) 
			- cwzx)
		self._screenPos[2] = math.floor((self._position[2] * zoomY)
			- cwzy)
		self._drawTable[6] = drawTable.zoomX
		self._drawTable[7] = drawTable.zoomY
	else
		self._screenPos[1] = self._position[1]
		self._screenPos[2] = self._position[2]
		self._drawTable[6] = 1
		self._drawTable[7] = 1
	end
	
	local text = drawTable.text
	self._drawTable[1] = self._text
	self._drawTable[2] = self._font
	self._drawTable[3] = self._color
	self._drawTable[4] = self._screenPos[1]
	self._drawTable[5] = self._screenPos[2]
	
	text[#text+1] = self._drawTable
end