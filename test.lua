local ucl = require 'ucl'
local pass = 0
local fail = 0
local skip = 0
local fails = {}

local colors = {
	default = 0, reset = 0,
	-- foreground colors
	black = 30, red = 31, green = 32, yellow = 33, 
	blue = 34, magenta = 35, cyan = 36, white = 37
}

local function cprint(n, ...)
	io.write("\027[" .. colors[n] .. 'm')
	print(...)
	io.write("\027[" .. colors.reset .. 'm')
end

local function cwrite(n, ...)
	io.write("\027[" .. colors[n] .. 'm')
	io.write(...)
	io.write("\027[" .. colors.reset .. 'm')
end

local function encode(s) 
	return s:gsub("([\r\n\t\\])", function(o) 
		if o == '\n' then return '\\n' end
		if o == '\r' then return '\\r' end
		if o == '\v' then return '\\v' end
		if o == '\t' then return '\\t' end
		if o == '\\' then return '\\\\' end
		return '?'
	end)
end

local test = function(interp, name, desc, filter, code, expected)
		if not expected then
			code, expected = filter, code
			filter = nil
		end

		local line = name.string .. ' ' .. desc.string
		if arg[1] ~= nil and not string.find(line, arg[1]) then
			return
		end

		if filter and (filter.string == "skip") then
			--cprint('white', "SKIP", name, desc)
			skip = skip + 1
			return
		end

		local ok, result = pcall(interp.eval, code.string)
		

		if ok and not result then
			fail = fail + 1
			cprint('red', "    " .. fail .. ") " .. line)
			fails[fail] = {name = line, error="No result"}
		elseif result.string == expected.string then
			cwrite('green', "    ✓ ")
			print(line)
			pass = pass + 1
		elseif not ok then
			fail = fail + 1	
			cprint('red', "    " .. fail .. ") " .. line)
			fails[fail] = {name = line, error=result}

		else
			fail = fail + 1
			cprint('red',"    " .. fail .. ") " .. line)
			fails[fail] = {name = line, error = "got " .. encode(result.string) .. " expected " .. encode(expected.string)}
		end
	end

local i = ucl.new()
i.commands.test = test
i.commands.bytestring = function(interp, v) return v end

local pfile = assert(io.popen(("find '%s' -maxdepth 1 -type f -print0"):format('tests'), 'r'))
local list = pfile:read('*a')
pfile:close()
for filename in list:gmatch('[^%z]+') do
    local h = assert(io.open(filename, 'r'))
    print()
    print(filename)
    local code = h:read('*a')
    h:close()
    local ok, err = xpcall(i.eval, debug.traceback, i, code)
    if not ok then
    	cprint('red', err)
    end
end



print()
print()
cprint('green', "  " .. pass .. " passing")
cprint('red', "  " .. fail .. " failing")
cprint('cyan', "  " .. skip .. " skipped")
print()
for k,v in pairs(fails) do
	print(' ' .. k .. ') ' .. v.name)
	cprint('red','    ' .. v.error)
	print()
end

print(arg[1])

