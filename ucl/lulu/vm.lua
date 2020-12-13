local tokenize = require('ucl.lulu.lexer').tokenize
local token_names = require('ucl.lulu.lexer').token_names
local Token = require('ucl.lulu.lexer').Token
local env = require('ucl.env')

local OP = {}
----------------------------------------------------------------------
--name               args    description
------------------------------------------------------------------------*/
OP.MOVE     = 0  --   A B     R(A) := R(B)                                    */
OP.LOADK    = 1  --   A Bx    R(A) := Kst(Bx)                                 */
OP.LOADKX   = 2  --   A       R(A) := Kst(extra arg)                          */
OP.LOADBOOL = 3  --   A B C   R(A) := (Bool)B; if (C) pc++                    */
OP.LOADNIL  = 4  --   A B     R(A), R(A+1), ..., R(A+B) := nil                */
OP.GETUPVAL = 5  --   A B     R(A) := UpValue[B]                              */

OP.GETTABUP = 6  --   A B C   R(A) := UpValue[B][RK(C)]                       */
OP.GETTABLE = 7  --   A B C   R(A) := R(B)[RK(C)]                             */ 

OP.SETTABUP = 8  --   A B C   UpValue[A][RK(B)] := RK(C)                      */
OP.SETUPVAL = 9  --   A B     UpValue[B] := R(A)                              */
OP.SETTABLE = 10 --   A B C   R(A)[RK(B)] := RK(C)                            */

OP.NEWTABLE = 11 --   A B C   R(A) := {} (size = B,C)                         */

OP.SELF     = 12 --   A B C   R(A+1) := R(B); R(A) := R(B)[RK(C)]             */

OP.ADD      = 13 --   A B C   R(A) := RK(B) + RK(C)                           */
OP.SUB      = 14 --   A B C   R(A) := RK(B) - RK(C)                           */
OP.MUL      = 15 --   A B C   R(A) := RK(B) * RK(C)                           */
OP.MOD      = 16 --   A B C   R(A) := RK(B) % RK(C)                           */
OP.POW      = 17 --   A B C   R(A) := RK(B) ^ RK(C)                           */
OP.DIV      = 18 --   A B C   R(A) := RK(B) / RK(C)                           */
OP.IDIV     = 19 --   A B C   R(A) := RK(B) // RK(C)                          */
OP.BAND     = 20 --   A B C   R(A) := RK(B) & RK(C)                           */
OP.BOR      = 21 --   A B C   R(A) := RK(B) | RK(C)                           */
OP.BXOR     = 22 --   A B C   R(A) := RK(B) ~ RK(C)                           */
OP.SHL      = 23 --   A B C   R(A) := RK(B) << RK(C)                          */
OP.SHR      = 24 --   A B C   R(A) := RK(B) >> RK(C)                          */
OP.UNM      = 25 --   A B     R(A) := -R(B)                                   */
OP.BNOT     = 26 --   A B     R(A) := ~R(B)                                   */
OP.NOT      = 27 --   A B     R(A) := not R(B)                                */
OP.LEN      = 28 --   A B     R(A) := length of R(B)                          */

OP.CONCAT   = 29 --   A B C   R(A) := R(B).. ... ..R(C)                       */

OP.JMP      = 30 --   A sBx   pc+=sBx; if (A) close all upvalues >= R(A - 1)  */
OP.EQ       = 31 --   A B C   if ((RK(B) == RK(C)) ~= A) then pc++            */
OP.LT       = 32 --   A B C   if ((RK(B) <  RK(C)) ~= A) then pc++            */
OP.LE       = 33 --   A B C   if ((RK(B) <= RK(C)) ~= A) then pc++            */

OP.TEST     = 34 --   A C     if not (R(A) <=> C) then pc++                   */
OP.TESTSET  = 35 --   A B C   if (R(B) <=> C) then R(A) := R(B) else pc++     */

OP.CALL     = 36 --   A B C   R(A), ... ,R(A+C-2) := R(A)(R(A+1), ... ,R(A+B-1)) */
OP.TAILCALL = 37 --   A B C   return R(A)(R(A+1), ... ,R(A+B-1))              */
OP.RETURN   = 38 --   A B     return R(A), ... ,R(A+B-2)      (see note)      */

OP.FORLOOP  = 39 --   A sBx   R(A)+=R(A+2);
                 --           if R(A) <?= R(A+1) then { pc+=sBx; R(A+3)=R(A) }*/
OP.FORPREP  = 40 --   A sBx   R(A)-=R(A+2); pc+=sBx                           */

OP.TFORCALL = 41 --   A C     R(A+3), ... ,R(A+2+C) := R(A)(R(A+1), R(A+2));  */
OP.TFORLOOP = 42 --   A sBx   if R(A+1) ~= nil then { R(A)=R(A+1); pc += sBx }*/

OP.SETLIST  = 43 --   A B C   R(A)[(C-1)*FPF+i] := R(A+i), 1 <= i <= B        */

OP.CLOSURE  = 44 --   A Bx    R(A) := closure(KPROTO[Bx])                     */

OP.VARARG   = 45 --   A B     R(A), R(A+1), ..., R(A+B-2) = vararg            */

OP.EXTRAARG = 46  --   Ax      extra (larger) argument for previous opcode     */

local op_names = {}
for k,v in pairs(OP) do op_names[v] = k end




local function exec(proto)
    local pc = 1
    local op = 0
    local R = {}
    local A, B, C

    while true do
        op, A, B, C = proto.op[pc], proto.A[pc], proto.B[pc], proto.C[pc]
        local RK = function(X) return R[X] end

        local Bx, sBx = B, B 

        if op == OP.MOVE then
            R[A] = R[B]
            pc = pc + 1
        elseif op == OP.LOADK then
            R[A] = B
            pc = pc + 1
        elseif op == OP.LOADBOOL then
            R[A] = B == 1
            if C == 1 then 
                pc = pc + 2
            else
                pc = pc + 1
            end
        elseif op == OP.LOADNIL then
            for i=A,A+B do
                R[A] = nil
            end
            pc = pc + 1
        elseif op == OP.GETTABUP then
            R[A] = _G[C]
            pc = pc + 1
        elseif op == OP.GETTABLE then
            -- TODO: Wrong
            if type(C) == "number" then
                R[A] = R[B][R[C]]
            else
                R[A] = R[B][C]
            end
            pc = pc + 1
        elseif op == OP.NEWTABLE then
            R[A] = {}
            pc = pc + 1
        elseif op == OP.ADD then
            R[A] = RK(B) + RK(C)
            pc = pc + 1
        elseif op == OP.SUB then
            R[A] = RK(B) - RK(C)
            pc = pc + 1
        elseif op == OP.MUL then
            R[A] = RK(B) * RK(C)
            pc = pc + 1
        elseif op == OP.MOD then
            R[A] = RK(B) % RK(C)
            pc = pc + 1
        elseif op == OP.POW then
            R[A] = math.pow(RK(B), RK(C))
            pc = pc + 1
        elseif op == OP.LEN then
            R[A] = #(R[B])
            pc = pc + 1
        elseif op == OP.CONCAT then
            local v = ''
            for i=B,C do
                v = R[A] .. R[i]
            end
            R[A] = v
            pc = pc + 1
        elseif op == OP.JMP then
            pc = pc + sBx + 1
            -- TODO CLOSE
        elseif op == OP.EQ then
            if  (R[B] == R[C]) ~= (A == 1) then
                pc = pc + 2
            else
                pc = pc + 1
            end
        elseif op == OP.LT then
            if  (R[B] < R[C]) ~= (A == 1) then
                pc = pc + 2
            else
                pc = pc + 1
            end
        elseif op == OP.LE then
            if  (R[B] <= R[C]) ~= (A == 1) then
                pc = pc + 2
            else
                pc = pc + 1
            end
        elseif op == OP.TEST then
            print("TST", R[A], C, not not R[A], not not C)
            if (not not R[A]) == (not not C) then
                pc = pc + 2
            else
                pc = pc + 1
            end
        elseif op == OP.CALL then
            local args = {}
            for i=A+1,A+B-1 do
                args[i-A] = R[i]
            end
            local r = { R[A](env.unpack(args)) }

            for i=1,C do
                R[A+i-1] = r[i]
            end

            pc = pc + 1
        elseif op == OP.RETURN then
            return
        else
            error("Unknown OpCode:" .. op_names[op])
        end

    end

end





return {
    OP = OP,
    op_names = op_names,
    exec = exec
}