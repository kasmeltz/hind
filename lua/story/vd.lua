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
	local params = params or {}
	
	params.infilename = params.infilename or 'points.dat'	
	savePoints(points, params.infilename)	
	params.infilename = 'TI ' .. params.infilename

	local qvoronoi_params = ''
	for k, v in pairs(params) do
		qvoronoi_params = qvoronoi_params .. v .. ' '
	end	
	
	local st = os.clock()
	local file = assert(io.popen('qhull\\qvoronoi ' .. qvoronoi_params .. ' o'))
	local output = file:read('*all')
	file:close()	
	print('QHULL o:' .. os.clock()-st)
	
	local st = os.clock()	
	local lines = output:split('\n')	
	local dims = lines[2]:split(' ')
	local numVertices = tonumber(dims[1])
	local corners = { x = {}, y = {} }
	for i = 3, 3 + numVertices - 1 do		
		local _, _, x, y = lines[i]:find('%s*(.-)%s+(.+)%s?')
		x = tonumber(x)
		y = tonumber(y)
		if x == -10.101 then x = math.huge end
		if y == -10.101 then y = math.huge end	
		corners.x[#corners.x + 1] = x
		corners.y[#corners.y +1] = y
	end	
	print('PARSE QHULL o:' .. os.clock()-st)

	local st = os.clock()	
	local file = assert(io.popen('qhull\\qvoronoi ' .. qvoronoi_params .. ' Fv'))
	local output = file:read('*all')
	file:close()
	print('QHULL Fv:' .. os.clock()-st)
	
	local centers = {}
	local adjacencies = {}
	
	local lines = output:split('\n')	
	for i = 2, #lines - 1 do
		local _, _, is1, is2, vx1, vx2 = lines[i]:find('%d+%s(%d+)%s(%d+)%s(%d+)%s(%d+)%s*')
		
		is1 = tonumber(is1) + 1
		is2 = tonumber(is2) + 1
		vx1 = tonumber(vx1) + 1
		vx2 = tonumber(vx2) + 1
		
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
	print('PARSE QHULL Fv:' .. os.clock()-st)


	return corners, centers, adjacencies
end
