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

function addFakeEdge(ad, po1, co1, co2)
	ad[#ad + 1] = { p1 = po1, p2 = po1, c1 = co1, c2 = co2 }
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
	
	addFakeVertex(co, 0.45, 0.5)
	addFakeVertex(co, 0.5, 0.45)
	addFakeVertex(co, 0.55, 0.5)
	addFakeVertex(co, 0.55, 0.6)
	addFakeVertex(co, 0.5, 0.65)
	addFakeVertex(co, 0.45, 0.6)
	
	addFakeEdge(ad, 1, 1, 2)
	addFakeEdge(ad, 1, 2, 3)
	addFakeEdge(ad, 1, 3, 4)
	addFakeEdge(ad, 1, 4, 5)
	addFakeEdge(ad, 1, 5, 6)

	addFakePoint(po, 0.25, 0.25)
	
	addFakeVertex(co, 0.2, 0.2)
	addFakeVertex(co, 0.45, 0.2)
	addFakeVertex(co, 0.45, 0.4)
	addFakeVertex(co, 0.3, 0.4)
	
	addFakeEdge(ad, 2, 7, 8)
	addFakeEdge(ad, 2, 8, 9)
	addFakeEdge(ad, 2, 9, 10)
	
	addFakePoint(po, 0.7, 0.7)
	
	addFakeVertex(co, 0.7, 0.6)
	addFakeVertex(co, 0.9, 0.8)
	addFakeVertex(co, 0.5, 0.8)
	
	addFakeEdge(ad, 3, 11, 12)
	addFakeEdge(ad, 3, 12, 13)
	
	addFakePoint(po, 0.7, 0.4)
	
	addFakeVertex(co, 0.7, 0.36)
	addFakeVertex(co, 0.75, 0.4)
	addFakeVertex(co, 0.7, 0.45)
	addFakeVertex(co, 0.66, 0.4)
	
	addFakeEdge(ad, 4, 14, 15)
	addFakeEdge(ad, 4, 15, 16)
	addFakeEdge(ad, 4, 16, 17)
	addFakeEdge(ad, 4, 17, 14)	
	
	local ce, co, ed = makeFakeGraph(po, co, ad)
		
	ce[1]._biome = 'ONE'
	ce[2]._biome = 'TWO'
	ce[3]._biome = 'THREE'
	ce[4]._biome = 'FOUR'
	
	local map = makeFakeMap(ce, co, ed)
	mapRasterizer = objects.MapRasterizer{ map }
	mapRasterizer:initialize(point:new(0,0), point:new(1,1), point:new(80,80))
	mapRasterizer._biomeMap = 
	{
		ONE = 1, 
		TWO = 2,
		THREE = 3,
		FOUR = 4,
		FIVE = 5,
		SIX = 6,
		SEVEN = 7,
		EIGHT = 8,
		NINE = 9
	}
		
	for _, c in pairs(ce) do
		print('CENTER #' .. c._id)
		print(c._rasterPoint)	
		print('EDGES')
		for _, b in pairs(c._borders) do
			print(b._v1._rasterPoint)
			print(b._v2._rasterPoint)
		end
	end	

	mapRasterizer:rasterize(point:new(24,24), point:new(40,40))
	print(string.rep('-',70))
	print(mapRasterizer)
	print(string.rep('-',70))
	
	print('Cells to raster')
	for k, v in pairs(mapRasterizer._cellsToRaster) do
		print(k,v)
	end	
end

test_simple_square()