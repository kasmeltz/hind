package.path = package.path .. ';..\\?.lua' 

require 'overworld_map'
require 'map_rasterizer'
require 'vdgraph'

function makeFakeVornoi()
	return 	{ x = {}, y = {} }, 			
			{ x = {}, y = {} },
			{}
end

function addFakePoint(po, x, y)
	po.x[#po.x + 1] = x
	po.y[#po.y + 1] = y
end

function addFakeVertex(co, x, y)
	co.x[#co.x + 1] = x
	co.y[#co.y + 1] = y
end

function addFakeEdge(ad, po1, po2, co1, co2)
	ad[#ad + 1] = { p1 = po1, p2 = po2, c1 = co1, c2 = co2 }
end

function makeFakeGraph(po, co, ad)
	return vdgraph.buildGraph(po, co, ad)		
end

function makeFakeMap(ce, co, ed)
	return objects.OverworldMap{ ce, co, ed }
end

function test_simple_square()
	local po, co, ad = makeFakeVornoi()
	
	addFakePoint(po, 0.5, 0.5)
	addFakePoint(po, 0.5, 0.6)
	addFakePoint(po, 0.8, 0.8)
	addFakePoint(po, 0.3, 0.3)
	
	addFakeVertex(co, 0.15, 0.55)
	addFakeVertex(co, 0.85, 0.55)
	addFakeVertex(co, 0.3, 0.65)
	addFakeVertex(co, 0.8, 0.65)
	addFakeVertex(co, 0.1, 0.4)
	addFakeVertex(co, 0.9, 0.4)
	
	addFakeEdge(ad, 1, 2, 1, 2)
	addFakeEdge(ad, 2, 3, 3, 4)
	addFakeEdge(ad, 4, 1, 5, 6)
	
	local ce, co, ed = makeFakeGraph(po, co, ad)
	
	ce[1]._biome = 'SHRUBLAND'
	ce[2]._biome = 'SCORCHED'
	ce[3]._biome = 'TAIGA'
	ce[4]._biome = 'GRASSLAND'
	
	local map = makeFakeMap(ce, co, ed)
	mapRasterizer = objects.MapRasterizer{ map }
	mapRasterizer:initialize(point:new(0,0), point:new(1,1), point:new(80,80))
		
	for _, c in pairs(ce) do
		print('CENTER')
		print(c._rasterPoint)	
		print('EDGES')
		for _, b in pairs(c._borders) do
			print(b._v1._rasterPoint)
			print(b._v2._rasterPoint)
		end
	end	

	mapRasterizer:rasterize(point:new(24,24), point:new(40,40))
	print(string.rep('-',40))
	print(mapRasterizer)
	print(string.rep('-',40))
	
	print('Cells to raster')
	for k, v in pairs(mapRasterizer._cellsToRaster) do
		print(k,v)
	end	
	
	print('Points to fill')
	for k, v in pairs(mapRasterizer._pointsToFill) do
		print(k,v)
	end		
end

test_simple_square()