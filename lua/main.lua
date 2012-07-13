--[[
	main.lua
	
	Created JUN-21-2012
]]

require 'factories'
require 'map'
require 'profiler'

local log = require 'log'
local ffi = require 'ffi'

function love.load()
	profiler = objects.Profiler{}
	terrainThread = love.thread.newThread('terrainGenerator', 
		'terrain_generator.lua')
	terrainThread:start()
	
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
	position = {500000*32,500000*32}
end

function love.draw()
	daMap:draw(daCamera)
	local zoomX = daCamera:viewport()[3] / daCamera:window()[3]
	local zoomY = daCamera:viewport()[4] / daCamera:window()[4]
	
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
		local x = ((v[1] * 32) - daCamera:window()[1]) * zoomX - ((32 / 2) * zoomX)
		local y = ((v[2] * 32) - daCamera:window()[2]) * zoomY - ((32 / 2) * zoomY)
		love.graphics.rectangle('line', x, y, 32 * zoomX, 32 * zoomY)
	end
	
	love.graphics.line(400-64,0,400-64,600)
	love.graphics.line(400+64,0,400+64,600)
	
	love.graphics.print('FPS: '..love.timer.getFPS(), 10, 0)	
	
	love.graphics.print('zoom: '.. zoom, 10, 20)	
		
	love.graphics.print('Camera: ' .. 		
		daCamera:window()[1] / 32 .. ', ' .. 
		daCamera:window()[2] / 32 .. ', ' .. 
		daCamera:window()[3] .. ', ' .. 
		daCamera:window()[4], 10, 40)	
			
	love.graphics.print('Map cells #' .. table.count(daMap._cells), 10, 60)
	local y = 80
	
	local err = terrainThread:get('error')
	if err then
		log.log('Error in Terrain Thread!')
		log.log(err)
	end
	
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
		position[1] = position[1] + 1
	end

	if love.keyboard.isDown('left') then
		position[1] = position[1] - 1
	end	

	if love.keyboard.isDown('up') then
		position[2] = position[2] - 1
	end

	if love.keyboard.isDown('down') then
		position[2] = position[2] + 1
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

	if zoom < 0.2 then zoom = 0.2 end
		
	daCamera:zoom(zoom)
	daCamera:center(position[1], position[2])
	
	daMap:update(dt, daCamera)
end