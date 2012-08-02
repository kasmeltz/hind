require 'vd'
require 'table_ext'

points = vd.generatePoints{ seed = os.time(), count = 6000 }
corners, centers, adjacencies = vd.voronoi(points)

--[[
print(table.dump(points))
print(table.dump(corners))
print(table.dump(edges))
print(table.dump(centers))
print(table.dump(adjacencies))
]]