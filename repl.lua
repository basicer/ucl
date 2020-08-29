local ucl = require 'ucl'

local readline = function(prompt)
	io.write(prompt)
	return io.read("*line")
end

local function add_history(s) end
local function read_history() end
local function write_history() end

local i = ucl.new()
i.flags.jit = 0
local interactive = i:interactive()

local function load_replxx()
	local rx = replxx.new()
	readline = function(s) return rx:input(s) end
	add_history = function(s) rx:history_add(s) end
	rx:set_completion_callback(function(m, len, ...)
		m = m:sub(-len)

		local words = interactive:complete(m)
		local out = {}
		for k,v in ipairs(words) do
			table.insert(out, Completion.new(v))
		end
		return out
	end)
	rx:set_hint_callback(function(text, len, ...)
		if #text > 14 then return {"faygo"} end
		if #text < 4 then return {} end
		return {
			text:sub(-len) .. " <- This is a hint: " .. table.concat({...}, "/"),
			"This is another hint",
			"Third hunt"
		}
	end)

end

local function load_ffi_readline()
	ffi.cdef[[
		char *readline(const char *);
		int	rl_initialize(void);
		int rl_attempted_completion_over;

		char * rl_line_buffer;


		typedef char **rl_completion_func_t (const char *, int, int);
		typedef char *rl_compentry_func_t (const char *, int);
		char **rl_completion_matches (const char *, rl_compentry_func_t *);
		rl_completion_func_t *rl_attempted_completion_function;

		void* malloc(size_t bytes);
		void free(void *);

		void using_history(void);
		int add_history(const char *);
		int read_history(const char *filename);
		int write_history(const char *filename);

	]]

	local matcher = ffi.cast("rl_compentry_func_t*", function(text, idx) end)

	function C.rl_attempted_completion_function(word, startpos, endpos)
		C.rl_attempted_completion_over = 1
		local m = ffi.string(word)

		local a,b = m:find("^[%[%]{}]+")
		local extra = ''
		if a then
			extra = m:sub(a,b)
			m = m:sub(a+1)
		end

		local words = interactive:complete(m)

		matcher:set(function(text, idx)
			if idx >= #words then
				return ffi.new('void*',nil)
			end
			local match = extra .. words[idx+1]
			local r = C.malloc(#match + 1)
			ffi.copy(r, match, #match + 1)
			return r
		end)
		return C.rl_completion_matches(word, matcher)
	end
	
	readline = function(prompt)
		local cstr = C.readline(prompt);
		if nil == cstr then return nil end
		local s = ffi.string(cstr);
		ffi.C.free(cstr)
		return s
	end

	add_history = function(s) return C.add_history(s) end
	write_history = function() return C.write_history(nil) end
	read_history = function() return C.read_history(nil) end
end




if rawget(_G, "replxx") then
	load_replxx()
else
	local haveffi, ffi = pcall(require,'ffi')
	if haveffi then

		local ok, C = pcall(ffi.load, "readline")

		if ok then
			load_ffi_readline()
		end
	end
end

if arg[1] then
	i:eval(io.open(arg[1], 'r'):read("*a"))
	os.exit()
end

interactive.add_history = add_history
read_history()
repeat
	local line = readline(interactive:prompt() .. "> ")
	if line ~= nil then
		interactive:line(line)
	end
until line == nil

print()
write_history()

