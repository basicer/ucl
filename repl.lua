local ucl = require 'ucl'
local env = require 'ucl.env'


local i = ucl.new()
i.flags.jit = 1
local interactive = i:interactive()

if arg[1] then
	local h, err = io.open(arg[1], 'r')
	if not h then error(err, 0) end
	i:eval(h:read("*a"))
	os.exit()
end

print(interactive:banner())



repeat
	local line, code = i:eval("read")
	if code ~= 0 and code ~= nil then break end

	local ok, rres = pcall(function()
		return i:eval(line)
	end)
	if ok then
		if rres ~= nil then
			print(rres)
		end
	else
		print(interactive:colorize('\n{red-fg}%s{/}\n', rres))
	end

until false

print()
--write_history()

