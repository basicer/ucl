local out = io.open(arg[1] or "out.lua", "w")

if arg[-1] then
	out:write("#!/usr/bin/env " .. arg[-1])
end

out:write([[

--
--                                    
--                _|_|_|    _|        
--  _|    _|    _|          _|        
--  _|    _|    _|          _|        
--  _|    _|    _|          _|        
--    _|_|_|      _|_|_|    _|_|_|_|  
--        _|                     
--        _|_|  Micro Command Language
--
--

local packages = {}
local loaded = {}
local iofill = {}
local files = {}

iofill.read = io.read
iofill.write = io.write
iofill.stdout = io.stdout
iofill.stderr = io.stderr
iofill.glob = function(where, pattern)
	local results = {}
	for k,v in pairs(files) do
		if k:match(pattern) then table.insert(results, k) end
	end
	return results
end

iofill.open = function(name) return {
	read = function(self, w) 
		assert(w == "*a")
		return files[name]
	end,
	close = function(seld) end
} end

local function req(file)
	if not loaded[file] then
		if not packages[file] then error("Unknown package " .. file) end
		loaded[file] = packages[file](req, iofill)
	end
	return loaded[file]
end

	]])


local function include(filename)
	local h = assert(io.open(filename, 'r'))
	print(filename)
	local code = h:read('*a')
	local moduleName = filename:gsub(".lua$", ""):gsub("/init", ""):gsub("/",".")
	loadstring(code) -- Make sure it compiles
	out:write("packages['" .. moduleName .. "'] = (function(require, io) ")
	out:write(code)
	out:write("\nend)\n\n")
	h:close()
end

local function glob(dir)
	local pfile = assert(io.popen(("find '%s' -maxdepth 1 -type f -print0"):format(dir), 'r'))
	local list = pfile:read('*a')
	pfile:close()
	return list:gmatch('[^%z]+')
end

for filename in glob('ucl') do
	include(filename)
end

for filename in glob('tests') do
	local h = io.open(filename, 'r')
	out:write('files["' .. filename .. '"] = [==[')
	out:write(h:read("*all"))
	out:write(' ]==]\n')
	h:close()
end



include("test.lua")
include("repl.lua")

out:write([[
	-- Try to detect if we are being executed by lua repl
	if getfenv and arg and not pcall(getfenv, 4) then
		if arg[1] == "--test" then
			table.remove(arg, 1)
			req('test')
		else
			req('repl')
		end
	end
	return req('ucl')

]])
