local ucl = require 'ucl'

local i = ucl.new()


repeat
	io.write("ucl> ")
	local line = io.read("*line")
	print(i:eval(line))
 until line == nil