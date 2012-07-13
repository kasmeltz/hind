--[[
	terrain_generator.lua
	
	Created JUL-13-2012
]]

local log = require 'log'
local ffi = require 'ffi'

require 'map'
require 'string_ext'

local thread = love.thread.getThread()

function generateCell(coords)
	local hash, x, y = objects.Map.hash(coords)	
	local filename = 'map/' .. hash .. '.dat'	
	log.log('Generating map cell: ' .. hash)
	
	local tileData = ffi.new('uint16_t[?]', objects.Map.cellShorts)	
	
	local block = objects.Map.cellSize * objects.Map.cellSize	
	for i = 0, block - 1 do
		local tileType = math.floor(math.random()*3)		
		tileData[i] = (tileType * 18) + 11
		if math.random() > 0.3 then
			tileData[i] = (tileType * 18) + (math.random() * 3) + 16
		end
	end
	for i = block, block * 2 - 1 do
		local tileType = math.floor(math.random()*3)		
		tileData[i] = (tileType * 18) + (math.random() * 15)
	end		
	for i = block * 2, block * 3 - 1 do
		local tileType = math.floor(math.random()*3)		
		tileData[i] = (tileType * 18) + (math.random() * 15)
	end				
	local bytes = ffi.string(tileData, objects.Map.cellBytes)
	local f = io.open(filename,'wb')
	f:write(bytes)
	f:close()	
end

-- signal that we are ready for a command
thread:set('ready', 'ok')
-- loop forever mwahahaha!
while true do
	local msg = thread:get('cmd')	
	if msg then
		log.log('Received message! "' .. msg .. '"')
		local cmd = msg:split('#')
		if cmd[1] == 'generate' then
			generateCell{cmd[2], cmd[3]}
		end
		
		-- ready for next command
		thread:set('ready', 'ok')
	end
end

