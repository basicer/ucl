local ucl = require 'ucl'

local readline = function()
	io.write("ucl> ")
	return io.read("*line")
end

local i = ucl.new()
i.flags.jit = 0

local haveffi, ffi = pcall(require,'ffi')


if haveffi then

	ffi.cdef[[
	char *readline(const char *);
	int	rl_initialize(void);

	void using_history(void);
	int add_history(const char *);
	void free(void *);
	]]

	local ok, C = pcall(ffi.load, "readline")


	if ok then
		readline = function()
			local cstr = C.readline("ucl> " );
			if nil == cstr then return nil end
			local s = ffi.string(cstr);
			ffi.C.free(cstr)
			C.add_history(s)
			return s
		end
	end
end

if arg[1] then
	i:eval(io.open(arg[1], 'r'):read("*a"))
	os.exit()
end

repeat
	local line = readline()
	if line ~= nil then
		local _, rres = pcall(function()
			return i:eval(line)
		end)
		if rres ~= nil then print(rres) end
	end
 until line == nil

 print()