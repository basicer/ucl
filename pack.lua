local pfile = assert(io.popen(("find '%s' -maxdepth 1 -type f -print0"):format('ucl'), 'r'))
local list = pfile:read('*a')
local out = io.open("out.lua", "w")

out:write([[

local packages = {}
local loaded = {}
local function req(file)
	if not loaded[file] then
		if not packages[file] then error("Unknown packages " .. file) end
		loaded[file] = packages[file](req)
	end
	return loaded[file]
end

]])

pfile:close()

local function include(filename)
	local h = assert(io.open(filename, 'r'))
    print()
    print(filename)
    print(code)
    local code = h:read('*a')
    local moduleName = filename:gsub(".lua$", ""):gsub("/init", "")
    out:write("packages['" .. moduleName .. "'] = (function(require) ")
    out:write(code)
    out:write("\nend)\n\n")
    h:close()
end

for filename in list:gmatch('[^%z]+') do
    include(filename)
end

include("main.lua")

out:write([[
	require.preload.ucl = function() return req('ucl') end
	--req("main")
]])