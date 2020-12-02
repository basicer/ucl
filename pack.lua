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

if io then
	iofill.read = io.read
	iofill.write = io.write
	iofill.stdout = io.stdout
	iofill.stderr = io.stderr
	iofill.flush = io.flush
end

iofill.glob = function(where, pattern)
	local results = {}
	for k,v in pairs(files) do
		if k:match(pattern) then table.insert(results, k) end
	end
	return results
end

iofill.open = function(name)
	if not files[name] then return io.open(name) end
	return {
		read = function(self, w)
			assert(w == "*a")
			return files[name]
		end,
		close = function(self) end
	}
end

local function req(file)
	if not loaded[file] then
		if not packages[file] then return require(file) end
		loaded[file] = packages[file](req, iofill)
	end
	return loaded[file]
end

	]])


local function include(filename)
	local loadstring = _G.loadstring or _G.load
	local h = assert(io.open(filename, 'r'))
	print(filename)
	local code = h:read('*a')
	local moduleName = filename:gsub(".lua$", ""):gsub("[\\/]","."):gsub("%.init", "")
	loadstring(code) -- Make sure it compiles
	out:write("packages['" .. moduleName .. "'] = (function(require, io) ")
	out:write(code)
	out:write("\nend)\n\n")
	h:close()
end

local function glob(dir)
	if jit and jit.os == "Windows" then
		local cdc = assert(io.popen("echo %cd%", "r"))
		local cd = cdc:read("*a"):gsub("%s+$", "")
		cdc:close()

		local pfile = assert(io.popen(("dir /B /s %s"):format(dir), 'r'))
		local list = pfile:read('*a')
		cd = cd:gsub("([%%-+])", function(c) return "%" .. c end)
		list = list:gsub(cd .. "\\", "")
		pfile:close()
		return list:gmatch('([^\r\n]+)')
	else
		local pfile = assert(io.popen(("find '%s' -maxdepth 2 -type f -print0"):format(dir), 'r'))
		local list = pfile:read('*a')
		pfile:close()
		return list:gmatch('[^%z]+')
	end
end

for filename in glob('ucl') do
	if filename ~= "ucl\\builtins" then
		include(filename)
	end
end

for filename in glob('tests') do
	local h = io.open(filename, 'r')
	local name = filename:gsub("\\", "/")
	out:write('files["' .. name .. '"] = [==[')
	out:write(h:read("*all"))
	out:write(' ]==]\n')
	h:close()
end



include("test.lua")
include("repl.lua")

out:write([[

-- Try to detect if we are being executed by lua repl
if _G.arg and debug and debug.getlocal and not pcall(debug.getlocal, 4, 1) then
	if _G.arg[1] == "--test" then
		table.remove(arg, 1)
		req('test')
	else
		req('repl')
	end
end
return req('ucl')

]])
