#NoTrayIcon
#include "lua.au3"
#include "lua_dlls.au3"

; Initialize library
_lua_Startup(_lua_ExtractDll())
OnAutoItExitRegister(_lua_Shutdown)

; -----------------------
; Example 01: hello world

ConsoleWrite(@CRLF & ">>> EXAMPLE 01: Hello world" & @CRLF)

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

; -----------------------------------------------------------------
; Example 02: calling lua function with arguments and return values

ConsoleWrite(@CRLF & ">>> EXAMPLE 02: Calling lua function with arguments and return values" & @CRLF)

; create new execution state
$pState = _luaL_newState()
_luaopen_base($pState) ; for tostring

; first add the function the environement
$iRet = _luaL_doString($pState, 'function sayHello(name, count) print("Hello " .. tostring(name)); return "Retval: Hello " .. tostring(name), "2nd param: " .. tostring(count) end')
If $iRet <> $LUA_OK Then
	; read the error description on top of the stack
	ConsoleWrite("!> Error: " & _lua_toString($pState, -1) & @CRLF)
	Exit
EndIf

; push the function sayHello on the top of the stack
_lua_getGlobal($pState, "sayHello")
ConsoleWrite("sayHello type: " & _luaL_typeName($pState, -1) & @CRLF) ; see that we have the function on the stack's top

; push the arguments
_lua_pushString($pState, "AutoIt!")
_lua_pushInteger($pState, 3)

; call the function
$iRet = _lua_pCall($pState, 2, $LUA_MULTRET)
If $iRet <> $LUA_OK Then
	; read the error description on top of the stack
	ConsoleWrite("!> Error: " & _lua_toString($pState, -1) & @CRLF)
	Exit
EndIf

; get return values
; in this case, we know that the function returns 2 results, it could be not always the case.
ConsoleWrite("Ret1: " & _lua_toString($pState, -2) & @CRLF)
ConsoleWrite("Ret2: " & _lua_toString($pState, -1) & @CRLF)

; close the state to free memory (you MUST call this function, this is not AutoIt's automatic memory management, it's a C library)
_lua_close($pState)


; --------------------------------------------
; Example 03: calling AutoIt function from lua

ConsoleWrite(@CRLF & ">>> EXAMPLE 03: Calling AutoIt function from lua" & @CRLF)

; create new execution state
$pState = _luaL_newState()

; In order to work with lua, AutoIt function must accepts 1 argument, and returns the number of return values (see lua documentation)
Func _myFunc($pState)
	; this function will simply display all arguments passed to it, and return no value
	ConsoleWrite("Entering AutoIt function..." & @CRLF)
	For $i = 1 To _lua_getTop($pState)
		ConsoleWrite(@TAB & "arg" & $i & " (" & _luaL_typeName($pState, $i) & "): " & _au3Lua_readAny($pState, $i, False) & @CRLF)
	Next
	Return 0
EndFunc

; push the AutoIt function, and set it to a global variable
_lua_pushCFunction($pState, _myFunc)
_lua_setGlobal($pState, "myFunc")

; execute lua script
$iRet = _luaL_doString($pState, 'myFunc(nil, true, false, 10, 20.5, "Hello, world!", {})')
If $iRet <> $LUA_OK Then
	; read the error description on top of the stack
	ConsoleWrite("!> Error: " & _lua_toString($pState, -1) & @CRLF)
	Exit
EndIf

; close the state to free memory (you MUST call this function, this is not AutoIt's automatic memory management, it's a C library)
_lua_close($pState)


; ----------------------------------------------------------------
; Example 04: passing and retreiveing AutoIt variables to/from lua

ConsoleWrite(@CRLF & ">>> EXAMPLE 04: Passing and retreiveing AutoIt variables to/from lua" & @CRLF)

; create new execution state
$pState = _luaL_newState()
_luaopen_base($pState)

; create an object
$oData = ObjCreate("Scripting.Dictionary")
$oData.Item("scriptfullpath") = @ScriptFullPath
$oData.Item("user") = @UserName & "@" & @ComputerName
$oData.Item("number") = 314

; push the variable and make it global
_au3Lua_pushAny($pState, $oData)
_lua_setGlobal($pState, "data")
$oData = Null

; execute lua script that will modify the table data
$iRet = _luaL_doString($pState, 'for k, v in pairs(data) do data[k] = tostring(v) .. " [Modified by LUA code]" end')
If $iRet <> $LUA_OK Then
	; read the error description on top of the stack
	ConsoleWrite("!> Error: " & _lua_toString($pState, -1) & @CRLF)
	Exit
EndIf

; retreive the modified data table
_lua_getGlobal($pState, "data")
$oData = _au3Lua_readAny($pState, -1, False)

For $sKey In $oData.Keys()
	ConsoleWrite(@TAB & $sKey & ": " & $oData.Item($sKey) & @CRLF)
Next

; close the state to free memory (you MUST call this function, this is not AutoIt's automatic memory management, it's a C library)
_lua_close($pState)
