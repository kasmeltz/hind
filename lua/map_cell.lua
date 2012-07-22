--[[
	map_cell.lua
	
	Created JUL-12-2012
]]

local ffi = require 'ffi'

local Object = (require 'object').Object

local log = require 'log'

local string, pairs, love 
	= string, pairs, love

module('objects')

MapCell = Object{ _init = { '_tileSet', '_size', '_coords', '_layers' } }

--
--  MapCell constructor
--
function MapCell:_clone(values)
	local o = Object._clone(self,values)
				
	-- create memory to hold the tiles
	local totalTiles = o._size[1] * o._size[2] * o._layers	
	o._tiles = ffi.new('uint16_t[?]', totalTiles)
	
	o._extents = { o._coords[1], o._coords[2],
		o._coords[1] + o._size[1] - 1,
		o._coords[2] + o._size[2] - 1 }
	
	-- the canvas that will hold the rendered version
	-- of this cell
	local tss = o._tileSet:size()
	o._canvas = love.graphics.newCanvas(
		o._size[1] * tss[1], o._size[2] * tss[2])
		
	o._rendered = false
	
	o.__tostring = function()
		return string.format('Map Cell -> l: %d, t: %d, r: %d, b: %d', 
			o._extents[1], o._extents[2], 
			o._extents[3], o._extents[4])
	end
		
	o._visible = false
	o._framesNotUsed = 0	
	o._hash = false
	
	return o
end

--
--  Renders the cell's tiles to the canvas
--
function MapCell:render()
	local tss = self._tileSet:size()	
	local tq = self._tileSet:quads()
	
	local s = love.timer.getMicroTime()
	self._canvas:renderTo( 
		function()
			local currentTile = 0
			local width = self._canvas:getWidth() - 1
			local height = self._canvas:getHeight() - 1		
			local sizeX = tss[1]
			local sizeY = tss[2]
			-- draw the tiles!
			for z = 1, self._layers do
				for y = 0, height, sizeY do
					for x = 0, width, sizeX do
						local tile = self._tiles[currentTile]
						if tile > 0 then				
							-- @TODO we should be using quads for map rendering with one BIG sprite atlas
							-- it is WAY faster
							--love.graphics.drawq(tq[tile]._image, tq[tile]._quad, x, y)
							love.graphics.draw(tq[tile], x, y)
						end
						currentTile = currentTile + 1
					end
				end
			end
		end)
	local e = love.timer.getMicroTime()		
	log.log('Rendering the map cell canvas took: ' .. e-s)
	
	self._rendered = true
end

--
--  Sets the tile data for this map cell
--
function MapCell:setTileData(data, bytes)
	ffi.copy(self._tiles, data, bytes)
	
	-- @todo reconstruct the tiles as necessary
	-- esp. collision boundaries
	
	-- @todo reconstruct the map objects
	-- including collision boundaries
end

--
--  Returns the canvas for the MapCell
--
function MapCell:canvas()
	if not self._rendered then self:render() end
	return self._canvas
end

-- 
--  Returns the map cell size
--
function MapCell:size()
	return self._size
end

--
--  Returns the spatial buckets 
--  that the object currently occupies
--
function MapCell:spatialBuckets(buckets)
	local tss = self._tileSet:size()
	
	local ids = {}

	for y = self._extents[2] * tss[2], self._extents[4] * tss[2], Map.bucketCellSize do
		for x = self._extents[1] * tss[1], self._extents[3] * tss[1], Map.bucketCellSize do
			ids[buckets.hash(x, y)] = true
		end
	end
	
	return ids
end

--
--  Registers the map cell in the proper
--	collision buckets - creating them if necessary
--
function MapCell:registerBuckets(buckets)
	-- calculates the spatial buckets
	self._bucketIds = self:spatialBuckets(buckets)
	
	-- register the new buckets ids
	for k, _ in pairs(self._bucketIds) do
		if not buckets[k] then
			buckets[k] = {}
			buckets['count' .. k] = 1
		else
			buckets['count' .. k] = buckets['count' .. k] + 1
		end		
	end	
end

--
--  Unregisters the map cell from the proper 
--	collision buckets - removing them if necessary
--
function MapCell:unregisterBuckets(buckets)
	-- unregister the buckets ids
	for k, _ in pairs(self._bucketIds) do
		buckets['count' .. k] = buckets['count' .. k] - 1
		if buckets['count' .. k] == 0 then
			buckets[k] = nil
		end		
	end	
end