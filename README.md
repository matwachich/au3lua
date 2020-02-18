### AutoIt3 Lua Wrapper
This is an AutoIt3 wrapper for the Lua scripting language. Consider it beta software, but since I will be using it in commercial product, expect it to evolve.

It has been developped with Lua 5.3.5. Updates will come for new Lua version.

Everything works just fine, except one (big) limitation: Anything that throws a Lua error (using C setjmp/longjmp functionality) will crash your AutoIt program. That means that it is impossible to use throw errors from an AutoIt function called by Lua (luaL_check\*, lua_error...).

### Simple example
```
#include <lua.au3>
#include <lua_dlls.au3>

; Initialize library
_lua_Startup(_lua_ExtractDll())
OnAutoItExitRegister(_lua_Shutdown)

; create new execution state
$pState = _luaL_newState()
_luaopen_base($pState) ; needed for the lua's print function

$iRet = _luaL_doString($pState, 'print("Hello, world!")')
If $iRet <> $LUA_OK Then
	; read the error description on top of the stack
	ConsoleWrite("!> Error: " & _lua_toString($pState, -1) & @CRLF)
	Exit
EndIf

; close the state to free memory (you MUST call this function, this is not AutoIt's automatic memory management, it's a C library)
_lua_close($pState)
```