--[[
	main.lua
	
	Created JUN-21-2012
]]

require 'factories'
require 'map'

local log = require 'log'
local ffi = require 'ffi'
print(ffi)

function love.load()
	screenWidth = 800
	screenHeight = 600
		local success = love.graphics.setMode( 
		screenWidth,screenHeight, false, false, 0 )		
	love.graphics.setColorMode('replace')

	tileSets = {}
	
	local load = {'outdoor'}
		
	for _, v in ipairs(load) do
		local ts = factories.createTileset('content/tilesets/' .. v .. '.dat')
		tileSets[ts:name()] = ts
	end
	
	daMap = factories.createMap('outdoor')
	
	daCamera = factories.createCamera()
	daCamera:window(500000*32,500000*32,screenWidth,screenHeight)
	daCamera:viewport(0,0,screenWidth,screenHeight)
	
	zoom = 1
end

function love.draw()
	daMap:draw(daCamera)
	
	local rects = {
		{ 500000, 500000 },
		{ 499990, 500000 },
		{ 499980, 500000 },
		{ 499970, 500000 },
		{ 499900, 500000 },
		{ 499870, 500000 },
		{ 500010, 500000 },
		{ 500020, 500000 },
		{ 500030, 500000 }, 
		{ 500050, 500000 },
		{ 500080, 500000 },
		{ 500100, 500000 }, 
		{ 500130, 500000 } 
	}
		
	for k, v in pairs(rects) do
		local x = v[1]*32 - daCamera:window()[1]
		local y = v[2]*32 - daCamera:window()[2]	
		love.graphics.rectangle('line', x, y, 32, 32)
	end
	
	love.graphics.print('FPS: '..love.timer.getFPS(), 10, 0)	
	
	love.graphics.print('zoom: '.. zoom, 10, 20)	
		
	love.graphics.print('Camera: ' .. 		
		daCamera:window()[1] / 32 .. ', ' .. 
		daCamera:window()[2] / 32 .. ', ' .. 
		daCamera:window()[3] .. ', ' .. 
		daCamera:window()[4], 10, 40)	
			
	love.graphics.print('Map cells #' .. table.count(daMap._cells), 10, 60)
	local y = 80
	
	--[[
	if daMap._drawingCells then
		for i = 1, #daMap._drawingCells do
			love.graphics.print(tostring(daMap._drawingCells[i]), 10, y)
			y=y+20
		end
	end	
	]]	
end

function love.update(dt)
	if love.keyboard.isDown('right') then
		daCamera._window[1] = daCamera._window[1] + 1
	end

	if love.keyboard.isDown('left') then
		daCamera._window[1] = daCamera._window[1] - 1
	end	

	if love.keyboard.isDown('up') then
		daCamera._window[2] = daCamera._window[2] - 1
	end

	if love.keyboard.isDown('down') then
		daCamera._window[2] = daCamera._window[2] + 1
	end		
	
	if love.keyboard.isDown('q') then
		zoom = 1
	end
	
	if love.keyboard.isDown('w') then
		zoom = 2
	end
	
	if love.keyboard.isDown('e') then
		zoom = 3
	end	
	
	if love.keyboard.isDown('r') then
		zoom = 4
	end		

	if love.keyboard.isDown('t') then
		zoom = 0.5
	end		
	
	if love.keyboard.isDown('a') then
		zoom = zoom + 0.01
	end
	
	if love.keyboard.isDown('z') then
		zoom = zoom - 0.01
	end		
	
	if love.keyboard.isDown('/') then
		os.exit()
	end		

	if zoom < 0.1 then zoom = 0.1 end
	
	daCamera:zoom(zoom)
end