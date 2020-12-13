local tokenize = require('ucl.lulu.lexer').tokenize
local token_names = require('ucl.lulu.lexer').token_names
local Token = require('ucl.lulu.lexer').Token
local env = require('ucl.env')
local OP = require('ucl.lulu.vm').OP
local op_names = require('ucl.lulu.vm').op_names

local state_mt = {}
function state_mt:need(t)
    assert(self.pos <= #self.tokens)
    if not self:is(t) then
        error("Expected " .. token_names[t] .. " found " .. token_names[self.tokens[self.pos][1]])
    end
    return self:eat(t)
end
function state_mt:is(t)
    assert(self.pos <= #self.tokens)
    return self.tokens[self.pos][1] == t
end
function state_mt:done()
	return self.pos > #self.tokens
end

function state_mt:eat(t)
    if not self:is(t) then return false end
    self.last = self.tokens[self.pos]
    self.pos = self.pos + 1
    self:chomp()
    return self.last
end

function state_mt:chomp()
    while self.tokens[self.pos] and self.tokens[self.pos][1] == Token.Comment do self.pos = self.pos + 1 end
end

function state_mt:panic(w)
    error("Unexpected " .. token_names[self.tokens[self.pos][1]] .. " while " .. w)
end

function state_mt:peek()
    return self.tokens[self.pos]
end

function state_mt:slot()
    local s = #self.slots + 1
    if self.maxslot < s then self.maxslot = s end
    self.slots[s] = 1
    return s - 1
end

function state_mt:take(s)
    s = s + 1
    assert(self.slots[s] == nil)
    if self.maxslot < s then self.maxslot = s end
    self.slots[s] = 1
end


function state_mt:release(s)
    s = s + 1
    self.slots[s] = nil
end

function state_mt:emitABC(op, a, b, c)
    local i = #self.proto.op + 1
    self.proto.op[i] = op
    self.proto.A[i] = a
    self.proto.B[i] = b
    self.proto.C[i] = c
    self.proto.L[i] = self.last[4]
end

function state_mt:emitAB(op, a, b)
    local i = #self.proto.op + 1
    self.proto.op[i] = op
    self.proto.A[i] = a
    self.proto.B[i] = b
    self.proto.L[i] = self.last[4]
end

function state_mt:emitABx(op, a, b)
    local i = #self.proto.op + 1
    self.proto.op[i] = op
    self.proto.A[i] = a
    self.proto.B[i] = b
    self.proto.L[i] = self.last[4]
end


local parseBlock, parseArgumentList, parseExp

local function parseIdentifier(s, slot)
    local name = s:need(Token.Name)
    local nn = s.source:sub(name[2], name[3])
    s:emitABC(OP.GETTABUP, slot, 0, tostring(nn))
    while true do
        if s:eat(Token.Dot) then
            local nxt = s:need(Token.Name)
            local nnxt = s.source:sub(nxt[2], nxt[3])
            s:emitABC(OP.GETTABLE, slot, slot, tostring(nnxt))
        elseif s:eat(Token.OpenBracket) then
            parseExp(s, slot+1)
            s:emitABC(OP.GETTABLE, slot, slot, slot+1)
            s:need(Token.CloseBracket)
        else
            break
        end
    end

end

local function parseSimpleExpr(s, slot)
    if s:eat(Token.Number) then
        s:emitABx(OP.LOADK, slot, tonumber(s.source:sub(s.last[2], s.last[3])))
    elseif s:eat(Token.Nil) then
        s:emitAB(OP.LOADNIL, slot, slot)
    elseif s:eat(Token.False) then
        s:emitABC(OP.LOADBOOL, slot, 0, 0)
    elseif s:eat(Token.True) then
        s:emitABC(OP.LOADBOOL, slot, 1, 0)
    elseif s:eat(Token.String) then
        s:emitABx(OP.LOADK, slot, s.source:sub(s.last[2] + s.last.os, s.last[3] - s.last.oe))
    elseif s:eat(Token.Elipsis) then
    elseif s:is(Token.Function) then
        error("Function expressions not supported.", 0)

    elseif s:is(Token.Name) then
        parseIdentifier(s, slot)

        if s:is(Token.OpenParen) then
            local args = parseArgumentList(s, slot+1)
            s:emitABC(OP.CALL, slot, args+1, 2)
            return
        end
    else
        s:panic("parsing expression")
    end
end

local opr_data = {
    ["or"]  = { l = 15, r = 15, b = false, op = OP.EQ },
    ["and"] = { l = 14, r = 14, b = false, op = OP.EQ },
    
    ["=="]  = { l = 13, r = 13, b = true, op = OP.EQ },
    ["~="]  = { l = 13, r = 13, b = true, op = OP.EQ },    
    [">"]   = { l = 13, r = 13, b = true, op = OP.EQ },
    ["<"]   = { l = 13, r = 13, b = true, op = OP.EQ },
    [">="]  = { l = 13, r = 13, b = true, op = OP.EQ },
    ["<="]  = { l = 13, r = 13, b = true, op = OP.EQ },    
     
    [".."]  = { l = 11, r = 12, b = false, op = OP.CONCAT },

    ["<<"]  = { l = 10, r = 10, b = false, op = OP.EQ },
    [">>"]  = { l = 10, r = 10, b = false, op = OP.EQ },


    ["+"]  = { l = 9 , r = 9 , b = false, op = OP.ADD },
    ["-"]  = { l = 9 , r = 9 , b = false, op = OP.SUB },


    ["%"]  = { l = 8 , r = 8 , b = false, op = OP.MOD },
    ["*"]  = { l = 8 , r = 8 , b = false, op = OP.MUL },
    ["/"]  = { l = 8 , r = 8 , b = false, op = OP.DIV },

    ["^"]  = { l = 6 , r = 7 , b = false, op = OP.POW },

}

local function parseExpPart(s, slot, max)
    parseSimpleExpr(s, slot)
    local op
    while true do
        if not op then op = s:eat(Token.Operator) end
        if not op then op = s:eat(Token.Minus) end
        if not op then break end
        local binop = s.source:sub(op[2], op[3])
        local nfo = opr_data[binop]
 
        if nfo.l >= max then
            return s.last
        end

        op = parseExpPart(s, slot + 1, nfo.r)
        
        if nfo.b then
            s:emitABC(nfo.op, 1, slot, slot + 1)
            s:emitABx(OP.JMP, 0, 1)
            s:emitABC(OP.LOADBOOL, slot, 0, 1)
            s:emitABC(OP.LOADBOOL, slot, 1, 0)
        else
            s:emitABC(nfo.op, slot, slot, slot + 1)
        end

        if not nfo then
            error("Unknwon operator: " .. binop)
        end
        
    end
end

parseExp = function(s, slot)
    return parseExpPart(s, slot, 20, 1)
end



local function parseIf(s)
    s:need(Token.If)
    local cond = s:slot()
    parseExp(s, cond)
    s:emitABC(OP.TEST, cond, 0, 1)
    s:emitABx(OP.JMP, 0, 3) --TODO: Jump target and close
    local tt = #s.proto.op

    s:need(Token.Then)
    parseBlock(s)
    while s:eat(Token.ElseIf) do
        parseBlock(s)
        s:need(Token.Then)
    end
    s:release(cond)
    s.proto.B[tt] = #s.proto.op - tt
end

parseArgumentList = function(s, slot)
    s:need(Token.OpenParen)
    local n = 0
    while true do
        if s:eat(Token.CloseParen) then return n end
        if n > 0 then s:need(Token.Comma) end
        s:take(slot+n)
        parseExp(s, slot + n)
        n = n + 1
    end
end

local function parseStat(s)
    if s:eat(Token.Local) then
        if s:eat(Token.Function) then
        
        end
        s:need(Token.Name)
        s:need(Token.Equals)
        parseExp(s, s:slot()) -- Should be explist
        return
    elseif s:is(Token.Break) then
        error("No suppport for break", 0)
    elseif s:is(Token.Goto) then
        error("No suppport for goto", 0)
    elseif s:is(Token.Do) then
        error("No suppport for do", 0)
    elseif s:eat(Token.While) then
        local cond = s:slot()
        parseExp(s, cond)
        s:emitABC(OP.TEST, cond, 0, 1)
        s:emitABx(OP.JMP, 0, 3)
        local tt = #s.proto.op
        s:need(Token.Do)
        parseBlock(s)
        s:need(Token.End)
        s.proto.B[tt] = #s.proto.op - tt
        return
    elseif s:eat(Token.Repeat) then
        local tt = #s.proto.op + 1
        parseBlock(s)
        s:need(Token.Until)
        local cond = s:slot()
        parseExp(s, cond)
        s:emitABC(OP.TEST, cond, 0, 1)
        s:emitABx(OP.JMP, 0, tt - #s.proto.op - 2)
        return
    elseif s:is(Token.If) then
        return parseIf(s)
    elseif s:eat(Token.For) then

        s:eat(Token.Name)
        s:need(Token.Equals)
        local start = s:slot()
        parseExp(s, start)
        s:need(Token.Comma)
        local stop = s:slot()
        parseExp(s, stop)
        local incr = s:slot()
        local var = s:slot()
        s:emitABx(OP.LOADK, incr, 1)

        s:need(Token.Do)

        s:emitABx(OP.FORPREP, start, 0)
        local tt = #s.proto.op

        parseBlock(s)

        s:need(Token.End)
        s:emitABx(OP.FORLOOP, start, tt - #s.proto.op - 1)
        s.proto.B[tt] = #s.proto.op - tt - 1

    elseif s:is(Token.Function) then
    elseif s:is(Token.Name) then
        local v = s:slot()
        parseIdentifier(s, v)

        if s:is(Token.OpenParen) then
            local args = parseArgumentList(s, v+1)
            s:emitABC(OP.CALL, v, args+1, 1)
            return
        end
        s:panic("Parsing nameish thing")
    else
        s:panic("parsing stat")
    end
end



parseBlock = function(s)
    while true do
        if s:is(Token.EOF) then break end
        if s:is(Token.End) then break end
        if s:is(Token.Until) then break end
        if s:is(Token.Return) then break end
        parseStat(s)
    end
    if s:eat(Token.Return) then
        parseExpList(s)
        s:eat(Token.SemiColon)
    end

end

local function compile(code)
    local tokens = tokenize(code)
    tokens[#tokens+1] = {Token.EOF}
    local state = setmetatable({
        source = tostring(code),
        tokens = tokens,
        pos = 1,
        slots = {},
        maxslot = 0,
        proto = {
            op = {},
            A = {},
            B = {},
            C = {},
            L = {}
        }
    }, {__index=state_mt})
    state:chomp()
    parseBlock(state)
    state:emitAB(OP.RETURN, 0, 0)

    local p = state.proto
    local o = {}
    table.insert(o, string.format("names <stdin:%d,%d> (%d instructions)", 0, 0, #p.op))
    table.insert(o, string.format("%d param, %d slots, %d upvalues, %d local, %d constants, %d functions", 0, state.maxslot, 0, 0, 0, 0))

    for i,op in ipairs(p.op) do
        local A, B, C = p.A[i] or '', p.B[i] or '', p.C[i] or ''
        local argz = string.format("%-6s %-6s %-6s", A, B, C):sub(1,20):gsub("\n", " ")
        table.insert(o, string.format("        %-8d [%d]     %-10s  %-20s ;", i, p.L[i], op_names[op], argz))
    end

    print(pcall(require('ucl.lulu.vm').exec,p))

    return table.concat(o, "\n")

end

return {
    compile = compile
}