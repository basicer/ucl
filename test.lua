local ucl = require 'ucl'
local argparse = require 'ucl/argparse'

local pass = 0
local fail = 0
local skip = 0
local badfails = 0
local fails = {}

local match = nil
local dir = 'tests'
local fmatch = '.'
local bail = false
local showall = false

local q = 1
while arg[q] do
	if arg[q] == '-a' then showall = true q = q + 1
	elseif arg[q] == '-b' then bail = true q = q + 1
	elseif arg[q] == '-g' then match = arg[q+1] q = q + 2 
	elseif arg[q] == '-d' then dir = arg[q+1] q = q + 2 
	elseif arg[q] == '-f' then fmatch = arg[q+1] q = q + 2 
	else error("Unknown flag: " .. arg[q]) end
end

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

local function runtest(test)
	local shouldFail = false
	if test.filter and test.filter.string == "skip" then
		if showall then cprint('white', "SKIP", name, desc) end
		skip = skip + 1
		return
	end

	if test.filter and test.filter.string:match("longIs") then
		if showall then cprint('white', "SKIP", name, desc) end
		skip = skip + 1
		return
	end

--

	if test.filter and (test.filter.string:match("fails")) then
		skip = skip + 1
		shouldFail = true
	end

	local ok, result = pcall(test.interp.eval, test.interp, test.code.string)
	

	if ok and not result then
		if shouldFail and not showall then return end
		fail = fail + 1
		cprint('red', "    " .. fail .. ") " .. test.line)
		fails[fail] = {name = test.line, error="No result"}
		if bail then os.exit(1) end
	elseif result.string == test.expected.string then
		if shouldFail then 
			cwrite('yellow', "    ? ")
			print(test.line)
			badfails = badfails + 1
			return
		end
		cwrite('green', "    ✓ ")
		print(test.line)
		pass = pass + 1
	elseif not ok then
		if shouldFail and not showall then return end
		fail = fail + 1	
		cprint('red', "    " .. fail .. ") " .. test.line)
		fails[fail] = {name = test.line, error=result}
		if bail then os.exit(1) end
	else
		if shouldFail and not showall then return end
		fail = fail + 1
		cprint('red',"    " .. fail .. ") " .. test.line)
		fails[fail] = {name = test.line, error = "got " .. encode(result.string) .. " expected " .. encode(test.expected.string)}
		if bail then os.exit(1) end
	end
end

local test = function(interp, ...)
	local opts = argparse('test name ?desc? ?constraints? body result ?-match? ?-returnCodes?')(...)

	local line = opts.name.string .. ' ' .. (opts.desc or ucl.Value.none).string:gsub("\n", " ")
	if match ~= nil and not string.find(line, match, 1, true) then
		return
	end

	runtest({
		name=opts.name, desc=opts.desc, filter=opts.constraints,
		code=opts.body, expected=opts.result,
		interp=interp, line=line
	})
end

local i = ucl.new()
i.commands.test = test
i.commands.bytestring = function(interp, v) return v end

for k,v in ipairs({
	'source', 'file', 'info', 'needs', 'testCmdConstraints',
	'rename', 'lsort', 'testreport'
}) do
	i.commands[v] =function(interp, f) return ucl.Value.none end
end

if not io.glob then 
	io.glob = function(dir, match)
		local result = {}
		local pfile = assert(io.popen(("find '%s' -maxdepth 1 -type f -print0"):format(dir), 'r'))
		local list = pfile:read('*a')
		pfile:close()
		for filename in list:gmatch('[^%z]+') do
			if filename:match(match) then table.insert(result, filename) end
		end
		return result
	end
end

local testFiles = io.glob(dir, fmatch)

-- testFiles = {"tests/misc.ucl"}

for k,filename in ipairs(testFiles) do
    local h = assert(io.open(filename, 'r'))
    print()
    print(filename)
    local code = h:read('*a')
    h:close()
    local ok, err = xpcall(function()
    	return i:eval(code)
    end, debug.traceback)
    if not ok then
    	cprint('red', err)
    end
end



print()
print()
cprint('green', "  " .. pass .. " passing")
cprint('red', "  " .. fail .. " failing")
cprint('cyan', "  " .. skip .. " skipped")
if badfails > 0 then
	cprint('yellow', "  " .. badfails .. " failing tests now passing :)")
end
print()
for k,v in pairs(fails) do
	print(' ' .. k .. ') ' .. v.name)
	cprint('red','    ' .. v.error)
	print()
end

if fail == 0 then
	os.exit(0)
else
	os.exit(1)
end

