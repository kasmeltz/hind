--[[
	tileset.lua
	
	Created JUN-21-2012
]]

module(..., package.seeall)

--
--  Creates a new map
--
function _M:new(t)
	self.__index = self    
	setmetatable(t, self)
	
	--
	-- Mark all of the object tiles for exclusion from regular tile set
	--
	t._quads = {}
	t._objects = {}		
	t._heights = {}	
	t._boundaries = {}
	
	for _, i in ipairs(t._images) do
		-- remove the object tiles from the base tiles
		local excludeTiles = {}		
		for _, def in pairs(i._definitions or {}) do
			for _, layer in pairs(def._tiles) do
				for k, v in pairs(layer) do
					excludeTiles[v] = true
				end
			end
		end
		
		-- build the regular tiles
		local tile = 1		
		local xPos = {}
		local yPos = {}
		
		for y = 0, i._image:getHeight() - 1, t._size[2] do
			for x = 0, i._image:getWidth() - 1, t._size[1] do					
				xPos[tile] = x
				yPos[tile] = y				
				if not excludeTiles[tile] then			
					local im = love.image.newImageData(t._size[1], t._size[2])
					im:paste(i._image,0,0,x,y,t._size[1],t._size[2])
					table.insert(t._quads, love.graphics.newImage(im))
					
					if i._heights then
						table.insert(t._heights, i._heights.default or i._heights[tile])
					end
					
					if i._boundaries then 
						table.insert(t._boundaries, i._boundaries.default or i._boundaries[tile])
					end
				end				
				tile = tile + 1
			end
		end
		
		-- build the objects
		for k, def in pairs(i._definitions or {}) do
			def._image = {}
			
			for layerNumber, layer in ipairs(def._tiles) do
				-- create new image data for this layer
				local im = love.image.newImageData(
					t._size[1] * def._tileWidth, 
					t._size[2] * def._tileHeight)	
				local tile = 1
				for y = 0, def._tileHeight - 1 do
					for x = 0, def._tileWidth - 1 do
						local sourceIndex = layer[tile]
						if sourceIndex then
							im:paste(i._image,x * t._size[1],y * t._size[2],
								xPos[sourceIndex],yPos[sourceIndex],t._size[1],t._size[2])
						end
						tile = tile + 1
					end
				end				
				def._image[layerNumber] = love.graphics.newImage(im)
			end
			
			def._tiles = nil
			t._objects[k] = def
		end
	end
	
	for _, i in pairs(t._images) do
		i.image = nil
	end

	return t
end


--
--  Returns the tile size
--
function _M:size()
	return self._size
end

--
--  Returns the image for this tileset
--
function _M:image()
	return self._image
end

--
--  Returns the tiles for this tileset
--
function _M:quads()
	return self._quads
end

--
--  Returns the tile bounaries table
--
function _M:boundaries()
	return self._boundaries
end

--
--  Returns the tile height table
--
function _M:heights()
	return self._heights
end

--
--  Returns the name of this tileset
--
function _M:name()
	return self._name
end