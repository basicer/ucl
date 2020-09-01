local ucl = require 'ucl'
local env = require 'ucl.env'


local i = ucl.new()
i.flags.jit = 0
local interactive = i:interactive()

local banner = {
	version = "0.1",
	load = env.loadstring and "+" or "-",
	bits = env.bit and "+" or "-",
	lua = env.lua,
	rltype = rltype,
	os = env.os
}

if arg[1] then
	i:eval(io.open(arg[1], 'r'):read("*a"))
	os.exit()
end

if env.tty then
	local banner = (([[
                               |
                       ##      |  Micro Command Language
     ##  ##    #####   ##      |
     ##  ##    ##      ##      |  Version: ${version}
     ######    #####   ####    |  ${lua} ${bits}bit ${load}load ${rltype}
         ###                   |
                               |
	]]):gsub('%${([^}]+)}', function(k)
		return banner[k]
	end))

	banner = env.colorize(banner:gsub("#", "{cyan-fg}{cyan-bg}#{/}"))
	print(banner)
end



repeat
	local line, code = i:eval("read")
	if code ~= 0 then break end

	local ok, rres = pcall(function()
		return i:eval(line)
	end)
	if ok then
		if rres ~= nil then
			print(rres)
		end
	else
		print(env.colorize('\n{red-fg}%s{/}\n', rres))
	end

until false

print()
--write_history()

