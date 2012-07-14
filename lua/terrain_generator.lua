--[[
	terrain_generator.lua
	
	Created JUL-13-2012
]]

local log = require 'log'
local ffi = require 'ffi'

require 'map'
require 'string_ext'

local thread = love.thread.getThread()

function generateCell(coords, replace)
	local hash, x, y = objects.Map.hash(coords)	
	local filename = 'map/' .. hash .. '.dat'	
	local f = io.open(filename,'r')
	if f and not replace then 
		-- cell already exists
		f:close()
		return 
	end
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

-- loop forever mwahahaha!
while true do
	local msg = thread:get('cmd')	
	if msg then
		-- log the message
		log.log('Received message! "' .. msg .. '"')
		local cmd = msg:split('#')
		if cmd[1] == 'generate' then
			for i = 2, #cmd, 2 do
				if cmd[i] and cmd[i+1] then
					generateCell{cmd[i], cmd[i+1]}
				end
			end
		end		
	end
end