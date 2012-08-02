--[[
	vd.lua
	
	Created JUL-30-2012
]]

package.path = package.path .. ';..\\?.lua' 

require 'string_ext'

local pairs, ipairs, io, os, assert, tonumber, math, print
	= pairs, ipairs, io, os, assert, tonumber, math, print
	
module(...)

function savePoints(points, filename)
	local filename = filename or 'points.dat'

	local fakePoints = {
		'-1 -1',
		'2 -1',
		'2 2',
		'-1 2'
	}
	
	local file = io.open(filename,'w')
	file:write(2)	
	file:write('\n')
	file:write(#points.x + #fakePoints)
	file:write('\n')

	for i = 1, #points.x do
		local x = points.x[i]
		local y = points.y[i]			
		file:write(x .. ' ' .. y)
		file:write('\n')
	end
	
	for _, v in ipairs(fakePoints) do
		file:write(v .. '\n')
	end

	file:close()
end

function generatePoints(params)
	local params = params or {}
	
	math.randomseed( params.seed )
	
	params.filename = params.filename or 'points.dat'		
	params.dimension = params.dimension or 2	
	params.count = params.count or 10
	
	local points = { x = {}, y = {} }
	
	for i = 1, params.count do
		local x = math.random() 
		local y = math.random()
		points.x[#points.x+1] = x 
		points.y[#points.y+1] = y		
	end
	
	return points, output
end

function voronoi(points, params)	
	local st = os.clock()
	
	local params = params or {}
	
	params.infilename = params.infilename or 'points.dat'	
	savePoints(points, params.infilename)	
	params.infilename = 'TI ' .. params.infilename

	local qvoronoi_params = ''
	for k, v in pairs(params) do
		qvoronoi_params = qvoronoi_params .. v .. ' '
	end	
	
	local file = assert(io.popen('qhull\\qvoronoi ' .. qvoronoi_params .. ' o'))
	local output = file:read('*all')
	file:close()
	
	print(os.clock()-st)
	
	local st = os.clock()
	
	local corners = { x = {}, y = {} }
	
	local lines = output:split('\n')
	
	local dims = lines[2]:split(' ')
	local numVertices = tonumber(dims[1])
	local numRegions = tonumber(dims[2])
	
	for i = 3, 3 + numVertices - 1 do
		local coords = lines[i]:split(' ')
		local xSet = false
		for j = 1, #coords do
			local s = tonumber(coords[j])
			if s == -10.101 then s = math.huge end
			if s then
				if not xSet then
					corners.x[#corners.x + 1] = tonumber(s)
					xSet = true
				else
					corners.y[#corners.y +1] = tonumber(s)
				end
			end
		end
	end	
	
	for i = 3 + numVertices, 3 + numVertices + numRegions - 1 do
		local points = {}
		
		local connections = lines[i]:split(' ')
		for j = 2, #connections-1 do
			points[#points+ 1] = tonumber(connections[j]) + 1
		end

		points[#points + 1] = tonumber(connections[#connections]) + 1
	end
	
	local centers = {}
	
	local file = assert(io.popen('qhull\\qvoronoi ' .. qvoronoi_params .. ' Fv'))
	local output = file:read('*all')
	file:close()
	
	local centers = {}
	local adjacencies = {}
	
	local lines = output:split('\n')
	
	for i = 2, #lines - 1 do
		local points = lines[i]:split(' ')
		local is1 = points[2] + 1
		local is2 = points[3] + 1
		local vx1 = points[4] + 1
		local vx2 = points[5] + 1
		
		adjacencies[#adjacencies + 1] = { p1 = is1, p2 = is2, c1 = vx1, c2 = vx2 }
		
		local center = centers[is1]
		if not center then
			center = {}
		end
		center[vx1] = true
		center[vx2] = true
		centers[is1] = center
		
		local center = centers[is2]
		if not center then
			center = {}
		end
		center[vx1] = true
		center[vx2] = true
		centers[is2] = center		
	end	

	print(os.clock()-st)


	return corners, centers, adjacencies
end
