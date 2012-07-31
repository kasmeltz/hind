require 'vd'
require 'table_ext'

points = vd.generatePoints{ count = 1000 }
corners, edges, regions, centers, adjacencies, delaunay = vd.voronoi(points)

--[[
print(table.dump(points))
print(table.dump(corners))
print(table.dump(edges))
print(table.dump(delaunay))
print(table.dump(regions))
print(table.dump(centers))
]]



