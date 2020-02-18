#include-once
#cs
LUA programming language wrapper for AutoIt3.
Developped for lua v5.3.

Nearly all lua C API functions are wrapped, with exception to functions that can raise an error because lua
uses C's setjmp/longjmp, and it seems that it is not supported by AutoIt (or am I missing something...).

Some C functions that are useless for AutoIt are not wrapped (see comments), and sometimes, 2 functions are
wrapped in only one AutoIt function with optional parameters.

There are some specific AutoIt functions:
_lua_ExtractDll, _lua_Startup, _lua_Terminate, _au3Lua_pushAny, _au3Lua_readAny, _au3Lua_dumpStack

Also, remember that lua C API is quite low level, so any error in stack indexes for example will result in
script crash without any error message!
#ce

; #VARIABLES# =========================================================================================================
Global $__gLua_hDLL = -1
; =====================================================================================================================

; #CONSTANTS# =========================================================================================================
; HEADER: lua.h

Const $LUA_VERSION_MAJOR = 5
Const $LUA_VERSION_MINOR = 3
Const $LUA_VERSION_NUM = 503 ; this is used by _luaL_checkversion to check if this UDF and DLLs versions are the same
							 ; so, if you want to use a DLL of different version, you must change this constant
							 ; and also the implementation of AutoIt wrappers if needed
Const $LUA_VERSION_RELEASE = 5

Const $LUA_VERSION = "Lua " & $LUA_VERSION_MAJOR & "." & $LUA_VERSION_MINOR
Const $LUA_RELEASE = $LUA_VERSION & "." & $LUA_VERSION_RELEASE
Const $LUA_COPYRIGHT = $LUA_RELEASE & "  Copyright (C) 1994-2018 Lua.org, PUC-Rio"
Const $LUA_AUTHORS = "R. Ierusalimschy, L. H. de Figueiredo, W. Celes"

; mark for precompiled code ('<esc>Lua')
Const $LUA_SIGNATURE = Binary("0x1b") & StringToBinary("Lua")

; option for multiple returns in 'lua_pcall' and 'lua_call'
Const $LUA_MULTRET = -1

; Pseudo-indices
; (-LUAI_MAXSTACK is the minimum valid index; we keep some free empty space after that to help overflow detection)
Const $LUA_REGISTRYINDEX = -1000000 - 1000 ; LUAI_MAXSTACK = 1000000 because on Windows LUAI_BITSINT >= 32
Func _lua_upvalueIndex($i)
	Return $LUA_REGISTRYINDEX - $i
EndFunc   ;==>_lua_upvalueIndex

; thread status
Const $LUA_OK = 0
Const $LUA_YIELD = 1
Const $LUA_ERRRUN = 2
Const $LUA_ERRSYNTAX = 3
Const $LUA_ERRMEM = 4
Const $LUA_ERRGCMM = 5
Const $LUA_ERRERR = 6

; basic types
Const $LUA_TNONE = -1
Const $LUA_TNIL = 0
Const $LUA_TBOOLEAN = 1
Const $LUA_TLIGHTUSERDATA = 2
Const $LUA_TNUMBER = 3
Const $LUA_TSTRING = 4
Const $LUA_TTABLE = 5
Const $LUA_TFUNCTION = 6
Const $LUA_TUSERDATA = 7
Const $LUA_TTHREAD = 8
Const $LUA_NUMTAGS = 9

; minimum Lua stack available to a C function
Const $LUA_MINSTACK = 20

; predefined values in the registry
Const $LUA_RIDX_MAINTHREAD = 1
Const $LUA_RIDX_GLOBALS = 2
Const $LUA_RIDX_LAST = $LUA_RIDX_GLOBALS

Const $LUA_OPADD = 0 ; ORDER TM, ORDER OP
Const $LUA_OPSUB = 1
Const $LUA_OPMUL = 2
Const $LUA_OPMOD = 3
Const $LUA_OPPOW = 4
Const $LUA_OPDIV = 5
Const $LUA_OPIDIV = 6
Const $LUA_OPBAND = 7
Const $LUA_OPBOR = 8
Const $LUA_OPBXOR = 9
Const $LUA_OPSHL = 10
Const $LUA_OPSHR = 11
Const $LUA_OPUNM = 12
Const $LUA_OPBNOT = 13

Const $LUA_OPEQ = 0
Const $LUA_OPLT = 1
Const $LUA_OPLE = 2

; Garbage collection function and options

Const $LUA_GCSTOP = 0
Const $LUA_GCRESTART = 1
Const $LUA_GCCOLLECT = 2
Const $LUA_GCCOUNT = 3
Const $LUA_GCCOUNTB = 4
Const $LUA_GCSTEP = 5
Const $LUA_GCSETPAUSE = 6
Const $LUA_GCSETSTEPMUL = 7
Const $LUA_GCISRUNNING = 9

; -----------------
; HEADER: lauxlib.h
; -----------------

; extra error code for 'luaL_loadfilex'
Const $LUA_ERRFILE = $LUA_ERRERR + 1

; key, in the registry, for table of loaded modules
Const $LUA_LOADED_TABLE = "_LOADED"

; key, in the registry, for table of preloaded loaders
Const $LUA_PRELOAD_TABLE = "_PRELOAD"

;~ Const $LUAL_NUMSIZES = 8*16 + 8 ; (sizeof(lua_Integer)*16 + sizeof(lua_Number))

; predefined references
Const $LUA_NOREF = -2
Const $LUA_REFNIL = -1

; standard library names
Const $LUA_COLIBNAME = "coroutine"
Const $LUA_TABLIBNAME = "table"
Const $LUA_IOLIBNAME = "io"
Const $LUA_OSLIBNAME = "os"
Const $LUA_STRLIBNAME = "string"
Const $LUA_UTF8LIBNAME = "utf8"
Const $LUA_BITLIBNAME = "bit32"
Const $LUA_MATHLIBNAME = "math"
Const $LUA_DBLIBNAME = "debug"
Const $LUA_LOADLIBNAME = "package"

; =====================================================================================================================

; =====================================================================================================================
; AutoIt specific helper functions
; =====================================================================================================================

; This function will extract either lua53_x86.dll or lua53_x64.dll according to @AutoItX64 and return DLLs full path,
; that can then be used as an argument to _lua_Startup.
; Note that this function will work only if lua_dlls.au3 is included to the script.
; On error, or if lua_dlls.au3 is not included, empty string "" is returned (which is default parameter to _lua_Startup)
;
Func _lua_ExtractDll($sFolder = @ScriptDir)
	$sFolder = $sFolder & "\lua53_" & (@AutoItX64 ? "x64" : "x86") & ".dll"
	Local $vRet = Call("_binFile_lua53_" & (@AutoItX64 ? "x64" : "x86") & "_dll", $sFolder)
	If Not $vRet Or (@error = 0xDEAD And @extended = 0xBEEF) Then Return ""
	Return $sFolder
EndFunc

Func _lua_Startup($sDllPath = "")
	If $__gLua_hDLL == -1 Then
		If Not $sDllPath Then
			$sDllPath = @AutoItX64 ? "lua53_x64.dll" : "lua53_x86.dll"
		EndIf
		$__gLua_hDLL = DllOpen($sDllPath)
		If $__gLua_hDLL == -1 Then Exit 0 * MsgBox(16, "Fatal Error", "Unable to load '" & $sDllPath & "'") - 1
	EndIf
	Return 1
EndFunc   ;==>_lua_Startup

Func _lua_Shutdown()
	If $__gLua_hDLL <> -1 Then
		DllClose($__gLua_hDLL)
		$__gLua_hDLL = -1
	EndIf
	Return 1
EndFunc   ;==>_lua_Terminate

; This function will read the lua value in stack index $iIdx and return it as AutoIt value
; values are converted to appropriate AutoIt value type:
; - nil/none                                  => Null
; - boolean                                   => Boolean
; - integer                                   => Integer
; - number                                    => Double
; - string                                    => either Binary or String (according to $bStringAsBinary)
; - thread, userdata, lightuserdata, function => Pointer
; - table                                     => Array (if metafield __au3array found) or Scripting.Dictionary
;
Func _au3Lua_readAny($pState, $iIdx, $bStringAsBinary = True)
	$iIdx = _lua_absIndex($pState, $iIdx)
	Switch _lua_type($pState, $iIdx)
		Case $LUA_TNIL, $LUA_TNONE
			Return Null
		Case $LUA_TBOOLEAN
			Return _lua_toBoolean($pState, $iIdx)
		Case $LUA_TNUMBER
			If _lua_isInteger($pState, $iIdx) Then
				Return _lua_toInteger($pState, $iIdx)
			Else
				Return _lua_toNumber($pState, $iIdx)
			EndIf
		Case $LUA_TSTRING ; lua strings are read as binary data (use BinaryToString to convert to actual string)
			Return $bStringAsBinary ? _lua_toBinary($pState, $iIdx) : _lua_toString($pState, $iIdx)
		Case $LUA_TTHREAD
			Return _lua_toThread($pState, $iIdx)
		Case $LUA_TFUNCTION
			Return _lua_toCFunction($pState, $iIdx)
		Case $LUA_TUSERDATA, $LUA_TLIGHTUSERDATA
			Return _lua_toUserdata($pState, $iIdx)
		Case $LUA_TTABLE
			If _luaL_getMetaField($pState, $iIdx, "__au3array") = $LUA_TNIL Then
				; Object by default
				_lua_pushNil($pState)
				Local $oRet = ObjCreate("Scripting.Dictionary")
				While _lua_next($pState, $iIdx)
					$oRet.Item(_au3Lua_readAny($pState, -2, False)) = _au3Lua_readAny($pState, -1, $bStringAsBinary)
					_lua_pop($pState, 1)
				WEnd
				_lua_pop($pState, 1)
				Return $oRet
			Else
				_lua_pop($pState, 1) ; pop metafield __au3array
				; if __au3array exists in object's metatable
				_lua_len($pState, $iIdx)
				Local $aRet[_lua_toInteger($pState, -1)]
				_lua_pop($pState, 1)
				For $i = 1 To UBound($aRet)
					_lua_rawGetI($pState, $iIdx, $i)
					$aRet[$i - 1] = _au3Lua_readAny($pState, -1, $bStringAsBinary)
					_lua_pop($pState, 1)
				Next
				Return $aRet
			EndIf
	EndSwitch
EndFunc   ;==>_au3Lua_readAny

; This function will push any AutoIt value to $pState lua stack
; values are converted to the appropriate lua type, with nested types supported (arrays in tables...):
; - Keyword/Null         => nil
; - Boolean              => boolean
; - Integers             => integer
; - Floats/Doubles       => number
; - String               => string (converted to UTF8)
; - Binary               => string (as is)
; - Array                => table[1 .. n] with metafield __au3array = true
; - Scription.Dictionary => table[keys] = values
; - UserFunction         => cfunction
;
Func _au3Lua_pushAny($pState, $vValue)
	Switch VarGetType($vValue)
		Case "Keyword"
			_lua_pushNil($pState)
		Case "Int32", "Int64"
			_lua_pushInteger($pState, $vValue)
		Case "Double"
			_lua_pushNumber($pState, $vValue)
		Case "String"
			_lua_pushString($pState, $vValue)
		Case "Binary"
			_lua_pushBinary($pState, $vValue)
		Case "Bool"
			_lua_pushBoolean($pState, $vValue)
		Case "Array"
			If UBound($vValue, 0) = 1 Then
				_lua_createTable($pState, UBound($vValue), 0)
				For $i = 0 To UBound($vValue) - 1
					_au3Lua_pushAny($pState, $vValue[$i])
					_lua_rawSetI($pState, -2, $i + 1)
				Next
				; set metatable to mark as Array
				_lua_newTable($pState)
				_lua_pushString($pState, "__au3array")
				_lua_pushBoolean($pState, True)
				_lua_setTable($pState, -3)
				_lua_setMetatable($pState, -2)
			Else
				Return SetError(1, 0, False) ; unsupported multi-dimensional arrays
			EndIf
		Case "Object"
			If ObjName($vValue, 2) = "Scripting.Dictionary" Then
				_lua_createTable($pState, 0, $vValue.Count)
				For $vKey In $vValue.Keys()
					_au3Lua_pushAny($pState, $vKey)
					_au3Lua_pushAny($pState, $vValue.Item($vKey))
					_lua_rawSet($pState, -3)
				Next
			Else
				Return SetError(1, 0, False) ; unsupported object
			EndIf
		Case "Function"
			Return SetError(1, 0, False) ; cannot push AutoIt functions
		Case "UserFunction"
			_lua_pushCFunction($pState, $vValue)
	EndSwitch
	Return True
EndFunc   ;==>_au3Lua_pushAny

Func _au3Lua_dumpStack($pState, $pfnCallback = ConsoleWrite)
	$pfnCallback("> Stack: ")
	For $i = 1 To _lua_getTop($pState)
		Switch _lua_type($pState, $i)
			Case $LUA_TNIL
				$pfnCallback("nil ")
			Case $LUA_TBOOLEAN, $LUA_TNUMBER
				$pfnCallback(_au3Lua_readAny($pState, $i) & " ")
			Case $LUA_TSTRING
				$pfnCallback('"' & _au3Lua_readAny($pState, $i) & '" ')
			Case Else
				$pfnCallback("'" & _lua_typeName($pState, _lua_type($pState, $i)) & "' ")
		EndSwitch
	Next
	$pfnCallback(@CRLF)
EndFunc   ;==>_au3Lua_dumpStack

; =====================================================================================================================
; HEADER: lua.h
; =====================================================================================================================

; ------------------
; State manipulation
; ------------------

;~ LUA_API lua_State *(lua_newstate) (lua_Alloc f, void *ud);
Func _lua_newState($pfnAlloc, $pUserData = 0)
	Local $aRet = DllCall($__gLua_hDLL, "ptr:cdecl", "lua_newstate", "ptr", __lua_helper_regFunc($pfnAlloc, "ptr:cdecl", "ptr;ptr;ulong_ptr;ulong_ptr"), "ptr", $pUserData)
	If @error Then Return SetError(@error, 0, Null)
	Return $aRet[0]
EndFunc   ;==>_lua_newState

;~ LUA_API void (lua_close) (lua_State *L);
Func _lua_close($pState)
	DllCall($__gLua_hDLL, "none:cdecl", "lua_close", "ptr", $pState)
EndFunc   ;==>_lua_close

;~ LUA_API lua_State *(lua_newthread) (lua_State *L);
Func _lua_newThread($pState)
	Local $aRet = DllCall($__gLua_hDLL, "ptr:cdecl", "_lua_newthread", "ptr", $pState)
	If @error Then Return SetError(@error, 0, Null)
	Return $aRet[0]
EndFunc   ;==>_lua_newThread

;~ LUA_API lua_CFunction (lua_atpanic) (lua_State *L, lua_CFunction panicf);
Func _lua_atPanic($pState, $pfnAtPanic)
	Local $aRet = DllCall($__gLua_hDLL, "ptr:cdecl", "lua_atpanic", "ptr", $pState, "ptr", __lua_helper_regFunc($pfnAtPanic, "int:cdecl", "ptr"))
	If @error Then Return SetError(@error, 0, Null)
	Return $aRet[0]
EndFunc   ;==>_lua_atPanic

;~ LUA_API const lua_Number *(lua_version) (lua_State *L);
Func _lua_version($pState = Null)
	Local $aRet = DllCall($__gLua_hDLL, "ptr:cdecl", "lua_version", "ptr", $pState)
	If @error Then Return SetError(@error, 0, 0)
	Return DllStructGetData(DllStructCreate("double", $aRet[0]), 1)
EndFunc   ;==>_lua_version


; ------------------------
; basic stack manipulation
; ------------------------

;~ LUA_API int (lua_absindex) (lua_State *L, int idx);
Func _lua_absIndex($pState, $iIdx)
	Local $aRet = DllCall($__gLua_hDLL, "int:cdecl", "lua_absindex", "ptr", $pState, "int", $iIdx)
	If @error Then Return SetError(@error, 0, 0)
	Return $aRet[0]
EndFunc   ;==>_lua_absIndex

;~ LUA_API int (lua_gettop) (lua_State *L);
Func _lua_getTop($pState)
	Local $aRet = DllCall($__gLua_hDLL, "int:cdecl", "lua_gettop", "ptr", $pState)
	If @error Then Return SetError(@error, 0, 0)
	Return $aRet[0]
EndFunc   ;==>_lua_getTop

;~ LUA_API void (lua_settop) (lua_State *L, int idx);
Func _lua_setTop($pState, $iIdx)
	Local $aRet = DllCall($__gLua_hDLL, "none:cdecl", "lua_settop", "ptr", $pState, "int", $iIdx)
	If @error Then Return SetError(@error, 0, False)
	Return True
EndFunc   ;==>_lua_setTop

;~ LUA_API void (lua_pushvalue) (lua_State *L, int idx);
Func _lua_pushValue($pState, $iIdx)
	Local $aRet = DllCall($__gLua_hDLL, "none:cdecl", "lua_pushvalue", "ptr", $pState, "int", $iIdx)
	If @error Then Return SetError(@error, 0, False)
	Return True
EndFunc   ;==>_lua_pushValue

;~ LUA_API void (lua_rotate) (lua_State *L, int idx, int n);
Func _lua_rotate($pState, $iIdx, $iN)
	Local $aRet = DllCall($__gLua_hDLL, "none:cdecl", "lua_rotate", "ptr", $pState, "int", $iIdx, "int", $iN)
	If @error Then Return SetError(@error, 0, False)
	Return True
EndFunc   ;==>_lua_rotate

;~ LUA_API void (lua_copy) (lua_State *L, int fromidx, int toidx);
Func _lua_copy($pState, $iFromIdx, $iToIdx)
	Local $aRet = DllCall($__gLua_hDLL, "none:cdecl", "lua_copy", "ptr", $pState, "int", $iFromIdx, "int", $iToIdx)
	If @error Then Return SetError(@error, 0, False)
	Return True
EndFunc   ;==>_lua_copy

;~ LUA_API int (lua_checkstack) (lua_State *L, int n);
Func _lua_checkStack($pState, $iN)
	Local $aRet = DllCall($__gLua_hDLL, "int:cdecl", "lua_checkstack", "ptr", $pState, "int", $iN)
	If @error Then Return SetError(@error, 0, False)
	Return $aRet[0] <> 0
EndFunc   ;==>_lua_checkStack

;~ LUA_API void (lua_xmove) (lua_State *from, lua_State *to, int n);
Func _lua_xMove($pFromState, $pToState, $iN)
	Local $aRet = DllCall($__gLua_hDLL, "none:cdecl", "lua_xmove", "ptr", $pFromState, "ptr", $pToState, "int", $iN)
	If @error Then Return SetError(@error, 0, False)
	Return True
EndFunc   ;==>_lua_xMove


; -----------------------------
; Access functions (stack -> C)
; -----------------------------

;~ LUA_API int (lua_isnumber) (lua_State *L, int idx);
Func _lua_isNumber($pState, $iIdx)
	Local $aRet = DllCall($__gLua_hDLL, "int:cdecl", "lua_isnumber", "ptr", $pState, "int", $iIdx)
	If @error Then Return SetError(@error, 0, False)
	Return $aRet[0] <> 0
EndFunc   ;==>_lua_isNumber

;~ LUA_API int (lua_isstring) (lua_State *L, int idx);
Func _lua_isString($pState, $iIdx)
	Local $aRet = DllCall($__gLua_hDLL, "int:cdecl", "lua_isstring", "ptr", $pState, "int", $iIdx)
	If @error Then Return SetError(@error, 0, False)
	Return $aRet[0] <> 0
EndFunc   ;==>_lua_isString

;~ LUA_API int (lua_iscfunction) (lua_State *L, int idx);
Func _lua_isCFunction($pState, $iIdx)
	Local $aRet = DllCall($__gLua_hDLL, "int:cdecl", "lua_iscfunction", "ptr", $pState, "int", $iIdx)
	If @error Then Return SetError(@error, 0, False)
	Return $aRet[0] <> 0
EndFunc   ;==>_lua_isCFunction

;~ LUA_API int (lua_isinteger) (lua_State *L, int idx);
Func _lua_isInteger($pState, $iIdx)
	Local $aRet = DllCall($__gLua_hDLL, "int:cdecl", "lua_isinteger", "ptr", $pState, "int", $iIdx)
	If @error Then Return SetError(@error, 0, False)
	Return $aRet[0] <> 0
EndFunc   ;==>_lua_isInteger

;~ LUA_API int (lua_isuserdata) (lua_State *L, int idx);
Func _lua_isUserdata($pState, $iIdx)
	Local $aRet = DllCall($__gLua_hDLL, "int:cdecl", "lua_isuserdata", "ptr", $pState, "int", $iIdx)
	If @error Then Return SetError(@error, 0, False)
	Return $aRet[0] <> 0
EndFunc   ;==>_lua_isUserdata

;~ LUA_API int (lua_type) (lua_State *L, int idx);
Func _lua_type($pState, $iIdx)
	Local $aRet = DllCall($__gLua_hDLL, "int:cdecl", "lua_type", "ptr", $pState, "int", $iIdx)
	If @error Then Return SetError(@error, 0, $LUA_TNONE)
	Return $aRet[0]
EndFunc   ;==>_lua_type

;~ LUA_API const char *(lua_typename) (lua_State *L, int tp);
Func _lua_typeName($pState, $iType)
	Local $aRet = DllCall($__gLua_hDLL, "str:cdecl", "lua_typename", "ptr", $pState, "int", $iType)
	If @error Then Return SetError(@error, 0, "")
	Return $aRet[0]
EndFunc   ;==>_lua_typeName


;~ LUA_API lua_Number (lua_tonumberx) (lua_State *L, int idx, int *isnum);
Func _lua_toNumber($pState, $iIdx)
	Local $aRet = DllCall($__gLua_hDLL, "double:cdecl", "lua_tonumberx", "ptr", $pState, "int", $iIdx, "int*", 0)
	If @error Then Return SetError(@error, 0, 0)
	Return SetError($aRet[3] = 0, 0, $aRet[0])
EndFunc   ;==>_lua_toNumber

;~ LUA_API lua_Integer (lua_tointegerx) (lua_State *L, int idx, int *isnum);
Func _lua_toInteger($pState, $iIdx)
	Local $aRet = DllCall($__gLua_hDLL, "int64:cdecl", "lua_tointegerx", "ptr", $pState, "int", $iIdx, "int*", 0)
	If @error Then Return SetError(@error, 0, 0)
	Return SetError($aRet[3] = 0, 0, $aRet[0])
EndFunc   ;==>_lua_toInteger

;~ LUA_API int (lua_toboolean) (lua_State *L, int idx);
Func _lua_toBoolean($pState, $iIdx)
	Local $aRet = DllCall($__gLua_hDLL, "int:cdecl", "lua_toboolean", "ptr", $pState, "int", $iIdx)
	If @error Then Return SetError(@error, 0, 0)
	Return $aRet[0] <> 0
EndFunc   ;==>_lua_toBoolean

;~ LUA_API const char *(lua_tolstring) (lua_State *L, int idx, size_t *len); TODO: test
Func _lua_toString($pState, $iIdx)
	Local $vRet = _lua_toBinary($pState, $iIdx)
	SetError(@error, @extended)
	Return BinaryToString($vRet, 4)
EndFunc   ;==>_lua_toString

Func _lua_toBinary($pState, $iIdx)
	Local $aRet = DllCall($__gLua_hDLL, "ptr:cdecl", "lua_tolstring", "ptr", $pState, "int", $iIdx, "ulong_ptr*", 0)
	If @error Then Return SetError(@error, 0, Binary(""))
	Return __lua_helper_ptr2bin($aRet[0], $aRet[3])
EndFunc   ;==>_lua_toBinary

;~ LUA_API size_t (lua_rawlen) (lua_State *L, int idx);
Func _lua_rawLen($pState, $iIdx)
	Local $aRet = DllCall($__gLua_hDLL, "ulong_ptr:cdecl", "lua_rawlen", "ptr", $pState, "int", $iIdx)
	If @error Then Return SetError(@error, 0, 0)
	Return $aRet[0]
EndFunc   ;==>_lua_rawLen

;~ LUA_API lua_CFunction (lua_tocfunction) (lua_State *L, int idx);
Func _lua_toCFunction($pState, $iIdx)
	Local $aRet = DllCall($__gLua_hDLL, "ptr:cdecl", "lua_tocfunction", "ptr", $pState, "int", $iIdx)
	If @error Then Return SetError(@error, 0, 0)
	Return $aRet[0]
EndFunc   ;==>_lua_toCFunction

;~ LUA_API void *(lua_touserdata) (lua_State *L, int idx);
Func _lua_toUserdata($pState, $iIdx)
	Local $aRet = DllCall($__gLua_hDLL, "ptr:cdecl", "lua_touserdata", "ptr", $pState, "int", $iIdx)
	If @error Then Return SetError(@error, 0, 0)
	Return $aRet[0]
EndFunc   ;==>_lua_toUserdata

;~ LUA_API lua_State *(lua_tothread) (lua_State *L, int idx);
Func _lua_toThread($pState, $iIdx)
	Local $aRet = DllCall($__gLua_hDLL, "ptr:cdecl", "lua_tothread", "ptr", $pState, "int", $iIdx)
	If @error Then Return SetError(@error, 0, 0)
	Return $aRet[0]
EndFunc   ;==>_lua_toThread

;~ LUA_API const void *(lua_topointer) (lua_State *L, int idx);
Func _lua_toPointer($pState, $iIdx)
	Local $aRet = DllCall($__gLua_hDLL, "ptr:cdecl", "lua_topointer", "ptr", $pState, "int", $iIdx)
	If @error Then Return SetError(@error, 0, 0)
	Return $aRet[0]
EndFunc   ;==>_lua_toPointer


; -----------------------------------
; Comparison and arithmetic functions
; -----------------------------------

;~ LUA_API void (lua_arith) (lua_State *L, int op);
Func _lua_arith($pState, $iOp)
	DllCall($__gLua_hDLL, "none:cdecl", "lua_arith", "ptr", $pState, "int", $iOp)
EndFunc   ;==>_lua_arith

;~ LUA_API int (lua_rawequal) (lua_State *L, int idx1, int idx2);
Func _lua_rawEqual($pState, $iIdx1, $iIdx2)
	Local $aRet = DllCall($__gLua_hDLL, "int:cdecl", "lua_rawequal", "ptr", $pState, "int", $iIdx1, "int", $iIdx2)
	If @error Then Return SetError(@error, 0, 0)
	Return $aRet[0]
EndFunc   ;==>_lua_rawEqual

;~ LUA_API int (lua_compare) (lua_State *L, int idx1, int idx2, int op);
Func _lua_compare($pState, $iIdx1, $iIdx2, $iOp)
	Local $aRet = DllCall($__gLua_hDLL, "int:cdecl", "lua_compare", "ptr", $pState, "int", $iIdx1, "int", $iIdx2, "int", $iOp)
	If @error Then Return SetError(@error, 0, 0)
	Return $aRet[0]
EndFunc   ;==>_lua_compare


; ---------------------------
; Push functions (C -> stack)
; ---------------------------

;~ LUA_API void (lua_pushnil) (lua_State *L);
Func _lua_pushNil($pState)
	DllCall($__gLua_hDLL, "none:cdecl", "lua_pushnil", "ptr", $pState)
	If @error Then Return SetError(@error, 0, False)
	Return True
EndFunc   ;==>_lua_pushNil

;~ LUA_API void (lua_pushnumber) (lua_State *L, lua_Number n);
Func _lua_pushNumber($pState, $fNumber)
	DllCall($__gLua_hDLL, "none:cdecl", "lua_pushnumber", "ptr", $pState, "double", $fNumber)
	If @error Then Return SetError(@error, 0, False)
	Return True
EndFunc   ;==>_lua_pushNumber

;~ LUA_API void (lua_pushinteger) (lua_State *L, lua_Integer n);
Func _lua_pushInteger($pState, $iInteger)
	DllCall($__gLua_hDLL, "none:cdecl", "lua_pushinteger", "ptr", $pState, "int64", $iInteger)
	If @error Then Return SetError(@error, 0, False)
	Return True
EndFunc   ;==>_lua_pushInteger

;~ LUA_API const char *(lua_pushlstring) (lua_State *L, const char *s, size_t len);
;~ LUA_API const char *(lua_pushstring) (lua_State *L, const char *s);
;~ LUA_API const char *(lua_pushvfstring) (lua_State *L, const char *fmt, va_list argp);
;~ LUA_API const char *(lua_pushfstring) (lua_State *L, const char *fmt, ...);
Func _lua_pushString($pState, $sString)
	Local $tBuf = __lua_helper_str2buf($sString)
	Local $iSize = @extended
	DllCall($__gLua_hDLL, "ptr:cdecl", "lua_pushlstring", "ptr", $pState, "struct*", $tBuf, "ulong_ptr", $iSize)
	If @error Then Return SetError(@error, 0, False)
	Return True
EndFunc   ;==>_lua_pushString

Func _lua_pushBinary($pState, $bBinary)
	Local $tBuf = DllStructCreate("byte[" & BinaryLen($bBinary) & "]")
	DllStructSetData($tBuf, 1, $bBinary)
	DllCall($__gLua_hDLL, "ptr:cdecl", "lua_pushlstring", "ptr", $pState, "struct*", $tBuf, "ulong_ptr", BinaryLen($bBinary))
	If @error Then Return SetError(@error, 0, False)
	Return True
EndFunc   ;==>_lua_pushBinary

;~ LUA_API void (lua_pushcclosure) (lua_State *L, lua_CFunction fn, int n);
Func _lua_pushCClosure($pState, $pfnCFunction, $iN)
	DllCall($__gLua_hDLL, "none:cdecl", "lua_pushcclosure", "ptr", $pState, "ptr", __lua_helper_regFunc($pfnCFunction, "int:cdecl", "ptr"), "int", $iN)
	If @error Then Return SetError(@error, 0, False)
	Return True
EndFunc   ;==>_lua_pushCClosure

;~ LUA_API void (lua_pushboolean) (lua_State *L, int b);
Func _lua_pushBoolean($pState, $bBoolean)
	DllCall($__gLua_hDLL, "none:cdecl", "lua_pushboolean", "ptr", $pState, "int", $bBoolean ? 1 : 0)
	If @error Then Return SetError(@error, 0, False)
	Return True
EndFunc   ;==>_lua_pushBoolean

;~ LUA_API void (lua_pushlightuserdata) (lua_State *L, void *p);
Func _lua_pushLightUserdata($pState, $pUserData)
	DllCall($__gLua_hDLL, "none:cdecl", "lua_pushlightuserdata", "ptr", $pState, "ptr", $pUserData)
	If @error Then Return SetError(@error, 0, False)
	Return True
EndFunc   ;==>_lua_pushLightUserdata

;~ LUA_API int (lua_pushthread) (lua_State *L);
Func _lua_pushThread($pState)
	Local $aRet = DllCall($__gLua_hDLL, "int:cdecl", "lua_pushthread", "ptr", $pState)
	If @error Then Return SetError(@error, 0, 0)
	Return $aRet[0]
EndFunc   ;==>_lua_pushThread


; ----------------------------
; Get functions (Lua -> stack)
; ----------------------------

;~ LUA_API int (lua_getglobal) (lua_State *L, const char *name);
Func _lua_getGlobal($pState, $sName)
	Local $aRet = DllCall($__gLua_hDLL, "int:cdecl", "lua_getglobal", "ptr", $pState, "str", $sName)
	If @error Then Return SetError(@error, 0, $LUA_TNONE)
	Return $aRet[0]
EndFunc   ;==>_lua_getGlobal

;~ LUA_API int (lua_gettable) (lua_State *L, int idx);
Func _lua_getTable($pState, $iIdx)
	Local $aRet = DllCall($__gLua_hDLL, "int:cdecl", "lua_gettable", "ptr", $pState, "int", $iIdx)
	If @error Then Return SetError(@error, 0, $LUA_TNONE)
	Return $aRet[0]
EndFunc   ;==>_lua_getTable

;~ LUA_API int (lua_getfield) (lua_State *L, int idx, const char *k);
Func _lua_getField($pState, $iIdx, $sKey)
	Local $aRet = DllCall($__gLua_hDLL, "int:cdecl", "lua_getfield", "ptr", $pState, "int", $iIdx, "str", $sKey)
	If @error Then Return SetError(@error, 0, $LUA_TNONE)
	Return $aRet[0]
EndFunc   ;==>_lua_getField

;~ LUA_API int (lua_geti) (lua_State *L, int idx, lua_Integer n);
Func _lua_getI($pState, $iIdx, $iN)
	Local $aRet = DllCall($__gLua_hDLL, "int:cdecl", "lua_geti", "ptr", $pState, "int", $iIdx, "int64", $iN)
	If @error Then Return SetError(@error, 0, $LUA_TNONE)
	Return $aRet[0]
EndFunc   ;==>_lua_getI

;~ LUA_API int (lua_rawget) (lua_State *L, int idx);
Func _lua_rawGet($pState, $iIdx)
	Local $aRet = DllCall($__gLua_hDLL, "int:cdecl", "lua_rawget", "ptr", $pState, "int", $iIdx)
	If @error Then Return SetError(@error, 0, $LUA_TNONE)
	Return $aRet[0]
EndFunc   ;==>_lua_rawGet

;~ LUA_API int (lua_rawgeti) (lua_State *L, int idx, lua_Integer n);
Func _lua_rawGetI($pState, $iIdx, $iN)
	Local $aRet = DllCall($__gLua_hDLL, "int:cdecl", "lua_rawgeti", "ptr", $pState, "int", $iIdx, "int64", $iN)
	If @error Then Return SetError(@error, 0, $LUA_TNONE)
	Return $aRet[0]
EndFunc   ;==>_lua_rawGetI

;~ LUA_API int (lua_rawgetp) (lua_State *L, int idx, const void *p);
Func _lua_rawGetP($pState, $iIdx, $pK)
	Local $aRet = DllCall($__gLua_hDLL, "int:cdecl", "lua_rawgetp", "ptr", $pState, "int", $iIdx, "ptr", $pK)
	If @error Then Return SetError(@error, 0, $LUA_TNONE)
	Return $aRet[0]
EndFunc   ;==>_lua_rawGetP


;~ LUA_API void (lua_createtable) (lua_State *L, int narr, int nrec);
Func _lua_createTable($pState, $nArr, $nRec)
	DllCall($__gLua_hDLL, "none:cdecl", "lua_createtable", "ptr", $pState, "int", $nArr, "int", $nRec)
	If @error Then Return SetError(@error, 0, False)
	Return True
EndFunc   ;==>_lua_createTable

;~ LUA_API void *(lua_newuserdata) (lua_State *L, size_t sz);
Func _lua_newUserdata($pState, $iSize)
	Local $aRet = DllCall($__gLua_hDLL, "ptr:cdecl", "lua_newuserdata", "ptr", $pState, "ulong_ptr", $iSize)
	If @error Then Return SetError(@error, 0, 0)
	Return $aRet[0]
EndFunc   ;==>_lua_newUserdata

;~ LUA_API int (lua_getmetatable) (lua_State *L, int objindex);
Func _lua_getMetatable($pState, $iIdx)
	Local $aRet = DllCall($__gLua_hDLL, "int:cdecl", "lua_getmetatable", "ptr", $pState, "int", $iIdx)
	If @error Then Return SetError(@error, 0, False)
	Return $aRet[0] <> 0
EndFunc   ;==>_lua_getMetatable

;~ LUA_API int (lua_getuservalue) (lua_State *L, int idx);
Func _lua_getUservalue($pState, $iIdx)
	Local $aRet = DllCall($__gLua_hDLL, "int:cdecl", "lua_getuservalue", "ptr", $pState, "int", $iIdx)
	If @error Then Return SetError(@error, 0, $LUA_TNONE)
	Return $aRet[0]
EndFunc   ;==>_lua_getUservalue


; ----------------------------
; Set functions (stack -> Lua)
; ----------------------------

;~ LUA_API void (lua_setglobal) (lua_State *L, const char *name);
Func _lua_setGlobal($pState, $sName)
	DllCall($__gLua_hDLL, "none:cdecl", "lua_setglobal", "ptr", $pState, "str", $sName)
	If @error Then Return SetError(@error, 0, False)
	Return True
EndFunc   ;==>_lua_setGlobal

;~ LUA_API void (lua_settable) (lua_State *L, int idx);
Func _lua_setTable($pState, $iIdx)
	DllCall($__gLua_hDLL, "none:cdecl", "lua_settable", "ptr", $pState, "int", $iIdx)
	If @error Then Return SetError(@error, 0, False)
	Return True
EndFunc   ;==>_lua_setTable

;~ LUA_API void (lua_setfield) (lua_State *L, int idx, const char *k);
Func _lua_setField($pState, $iIdx, $sKey)
	DllCall($__gLua_hDLL, "none:cdecl", "lua_setfield", "ptr", $pState, "int", $iIdx, "str", $sKey)
	If @error Then Return SetError(@error, 0, False)
	Return True
EndFunc   ;==>_lua_setField

;~ LUA_API void (lua_seti) (lua_State *L, int idx, lua_Integer n);
Func _lua_setI($pState, $iIdx, $iN)
	DllCall($__gLua_hDLL, "none:cdecl", "lua_seti", "ptr", $pState, "int", $iIdx, "int64", $iN)
	If @error Then Return SetError(@error, 0, False)
	Return True
EndFunc   ;==>_lua_setI

;~ LUA_API void (lua_rawset) (lua_State *L, int idx);
Func _lua_rawSet($pState, $iIdx)
	DllCall($__gLua_hDLL, "none:cdecl", "lua_rawset", "ptr", $pState, "int", $iIdx)
	If @error Then Return SetError(@error, 0, False)
	Return True
EndFunc   ;==>_lua_rawSet

;~ LUA_API void (lua_rawseti) (lua_State *L, int idx, lua_Integer n);
Func _lua_rawSetI($pState, $iIdx, $iN)
	DllCall($__gLua_hDLL, "none:cdecl", "lua_rawseti", "ptr", $pState, "int", $iIdx, "int64", $iN)
	If @error Then Return SetError(@error, 0, False)
	Return True
EndFunc   ;==>_lua_rawSetI

;~ LUA_API void (lua_rawsetp) (lua_State *L, int idx, const void *p);
Func _lua_rawSetP($pState, $iIdx, $pK)
	DllCall($__gLua_hDLL, "none:cdecl", "lua_rawsetp", "ptr", $pState, "int", $iIdx, "ptr", $pK)
	If @error Then Return SetError(@error, 0, False)
	Return True
EndFunc   ;==>_lua_rawSetP

;~ LUA_API int (lua_setmetatable) (lua_State *L, int objindex); ????? in the online manual, return value is void
Func _lua_setMetatable($pState, $iIdx)
	Local $aRet = DllCall($__gLua_hDLL, "int:cdecl", "lua_setmetatable", "ptr", $pState, "int", $iIdx)
	If @error Then Return SetError(@error, 0, False)
	Return $aRet[0]
EndFunc   ;==>_lua_setMetatable

;~ LUA_API void (lua_setuservalue) (lua_State *L, int idx);
Func _lua_setUservalue($pState, $iIdx)
	DllCall($__gLua_hDLL, "none:cdecl", "lua_setuservalue", "ptr", $pState, "int", $iIdx)
	If @error Then Return SetError(@error, 0, False)
	Return True
EndFunc   ;==>_lua_setUservalue


; ---------------------------------------------------
; 'load' and 'call' functions (load and run Lua code)
; ---------------------------------------------------

;~ LUA_API void (lua_callk) (lua_State *L, int nargs, int nresults,lua_KContext ctx, lua_KFunction k);
;~ #define lua_call(L,n,r) lua_callk(L, (n), (r), 0, NULL)
Func _lua_call($pState, $iNArgs, $iNResults = $LUA_MULTRET, $pKContext = Null, $pKFunction = Null)
	DllCall($__gLua_hDLL, "none:cdecl", "lua_callk", "ptr", $pState, "int", $iNArgs, "int", $iNResults, "ptr", $pKContext, "ptr", $pKFunction)
	If @error Then Return SetError(@error, 0, False)
	Return True
EndFunc   ;==>_lua_call

;~ LUA_API int (lua_pcallk) (lua_State *L, int nargs, int nresults, int errfunc, lua_KContext ctx, lua_KFunction k);
;~ #define lua_pcall(L,n,r,f) lua_pcallk(L, (n), (r), (f), 0, NULL)
Func _lua_pCall($pState, $iNArgs, $iNResults = $LUA_MULTRET, $iErrFuncIdx = 0, $pKContext = Null, $pKFunction = Null)
	Local $aRet = DllCall($__gLua_hDLL, "int:cdecl", "lua_pcallk", "ptr", $pState, "int", $iNArgs, "int", $iNResults, "int", $iErrFuncIdx, "ptr", $pKContext, "ptr", $pKFunction)
	If @error Then Return SetError(@error, 0, $LUA_ERRRUN)
	Return $aRet[0]
EndFunc   ;==>_lua_pCall

;~ LUA_API int (lua_load) (lua_State *L, lua_Reader reader, void *dt, const char *chunkname, const char *mode);
Func _lua_load($pState, $vData, $sChunkname = "", $sMode = "bt")
	Local $tUserData = DllStructCreate("ptr Buf; ulong_ptr Size; bool Done")
	Local $tBuf = __lua_helper_str2buf($vData, False)
	Local $iSize = @extended
	$tUserData.Buf = DllStructGetPtr($tBuf)
	$tUserData.Size = $iSize
	$tUserData.Done = False

	Local $aRet = DllCall($__gLua_hDLL, "int:cdecl", "lua_load", _
			"ptr", $pState, _
			"ptr", __lua_helper_regFunc(__lua_load_reader, "ptr:cdecl", "ptr;ptr;ulong_ptr"), _
			"struct*", $tUserData, _
			"str", $sChunkname, "str", $sMode _
			)
	If @error Then Return SetError(@error, 0, -1)
	Return $aRet[0]
EndFunc   ;==>_lua_load
Func __lua_load_reader($pState, $pUserData, $pSize)
	Local $tUserData = DllStructCreate("ptr Buf; ulong_ptr Size; bool Done", $pUserData)
	If Not $tUserData.Done Then
		DllStructSetData(DllStructCreate("ulong_ptr", $pSize), 1, $tUserData.Size)
		$tUserData.Done = True
		Return $tUserData.Buf
	Else
		Return Null
	EndIf
EndFunc   ;==>__lua_load_reader

;~ LUA_API int (lua_dump) (lua_State *L, lua_Writer writer, void *data, int strip);
Func _lua_dump($pState, $bStrip = False)
	Local $tUserData = DllStructCreate("handle Heap; ptr Mem; ulong_ptr Size; ulong_ptr Offset")
	$tUserData.Heap = DllCall("kernel32.dll", "handle", "GetProcessHeap")[0]
	$tUserData.Mem = DllCall("kernel32.dll", "ptr", "HeapAlloc", "handle", $tUserData.Heap, "dword", 0, "ulong_ptr", 4096)[0]
	$tUserData.Size = 4096
	$tUserData.Offset = 0

	Local $aRet = DllCall($__gLua_hDLL, "int:cdecl", "lua_dump", "ptr", $pState, "ptr", __lua_helper_regFunc(__lua_dump_writer, "int:cdecl", "ptr;ptr;ulong_ptr;ptr"), "struct*", $tUserData, "int", $bStrip)
	If @error Then Return SetError(@error, 0, -1)

	If $aRet[0] = 0 Then
		$aRet[0] = DllStructGetData(DllStructCreate("byte[" & $tUserData.Offset & "]", $tUserData.Mem), 1)
	Else
		SetError($aRet[0])
		$aRet[0] = -1
	EndIf

	DllCall("kernel32", "bool", "HeapFree", "handle", $tUserData.Heap, "dword", 0, "ptr", $tUserData.Mem)
	Return $aRet[0]
EndFunc   ;==>_lua_dump
Func __lua_dump_writer($pState, $pData, $iSize, $pUserData)
	Local $tUserData = DllStructCreate("handle Heap; ptr Mem; ulong_ptr Size; ulong_ptr Offset", $pUserData)
	While $tUserData.Size < $tUserData.Offset + $iSize
		$tUserData.Mem = DllCall("kernel32.dll", "ptr", "HeapReAlloc", "handle", $tUserData.Heap, "dword", 0, "ptr", $tUserData.Mem, "ulong_ptr", $tUserData.Size + 4096)
		$tUserData.Size += 4096
	WEnd
	DllCall("kernel32.dll", "none", "RtlMoveMemory", "struct*", $pData, "struct*", $tUserData.Mem + $tUserData.Offset, "ulong_ptr", $iSize) ; avoid Memory.au3 depandancy
	$tUserData.Offset += $iSize
	Return 0
EndFunc   ;==>__lua_dump_writer


; -------------------
; coroutine functions
; -------------------

; will this work with AutoIt???

;~ LUA_API int (lua_yieldk) (lua_State *L, int nresults, lua_KContext ctx, lua_KFunction k);
;~ #define lua_yield(L,n) lua_yieldk(L, (n), 0, NULL)
Func _lua_yield($pState, $iNResults, $pKContext = Null, $pKFunction = Null)
	Local $aRet = DllCall($__gLua_hDLL, "int:cdecl", "lua_yieldk", "ptr", $pState, "int", $iNResults, "ptr", $pKContext, "ptr", $pKFunction)
	If @error Then Return SetError(@error, 0, 0)
	Return $aRet[0]
EndFunc   ;==>_lua_yield

;~ LUA_API int (lua_resume) (lua_State *L, lua_State *from, int narg);
Func _lua_resume($pState, $pFromState, $iNArgs)
	Local $aRet = DllCall($__gLua_hDLL, "int:cdecl", "lua_resume", "ptr", $pState, "ptr", $pFromState, "int", $iNArgs)
	If @error Then Return SetError(@error, 0, 0)
	Return $aRet[0]
EndFunc   ;==>_lua_resume

;~ LUA_API int (lua_status) (lua_State *L);
Func _lua_status($pState)
	Local $aRet = DllCall($__gLua_hDLL, "int:cdecl", "lua_status", "ptr", $pState)
	If @error Then Return SetError(@error, 0, -1)
	Return $aRet[0]
EndFunc   ;==>_lua_status

;~ LUA_API int (lua_isyieldable) (lua_State *L);
Func _lua_isYieldable($pState)
	Local $aRet = DllCall($__gLua_hDLL, "int:cdecl", "lua_isyieldable", "ptr", $pState)
	If @error Then Return SetError(@error, 0, 0)
	Return $aRet[0]
EndFunc   ;==>_lua_isYieldable


; ---------------------------------------
; garbage-collection function and options
; ---------------------------------------

;~ LUA_API int (lua_gc) (lua_State *L, int what, int data);
Func _lua_gc($pState, $iWhat, $iData)
	Local $aRet = DllCall($__gLua_hDLL, "int:cdecl", "lua_gc", "ptr", $pState, "int", $iWhat, "int", $iData)
	If @error Then Return SetError(@error, 0, 0)
	Return $aRet[0]
EndFunc   ;==>_lua_gc


; -----------------------
; miscellaneous functions
; -----------------------

;~ LUA_API int (lua_error) (lua_State *L);
Func _lua_error($pState)
	Local $aRet = DllCall($__gLua_hDLL, "int:cdecl", "lua_error", "ptr", $pState)
	If @error Then Return SetError(@error, 0, 0)
	Return $aRet[0] ; function never returns
EndFunc   ;==>_lua_error

;~ LUA_API int (lua_next) (lua_State *L, int idx);
Func _lua_next($pState, $iIdx)
	Local $aRet = DllCall($__gLua_hDLL, "int:cdecl", "lua_next", "ptr", $pState, "int", $iIdx)
	If @error Then Return SetError(@error, 0, 0)
	Return $aRet[0]
EndFunc   ;==>_lua_next

;~ LUA_API void (lua_concat) (lua_State *L, int n);
Func _lua_concat($pState, $iN)
	DllCall($__gLua_hDLL, "none:cdecl", "lua_concat", "ptr", $pState, "int", $iN)
	If @error Then Return SetError(@error, 0, False)
	Return True
EndFunc   ;==>_lua_concat

;~ LUA_API void (lua_len) (lua_State *L, int idx);
Func _lua_len($pState, $iIdx)
	DllCall($__gLua_hDLL, "none:cdecl", "lua_len", "ptr", $pState, "int", $iIdx)
	If @error Then Return SetError(@error, 0, False)
	Return True
EndFunc   ;==>_lua_len

;~ LUA_API size_t (lua_stringtonumber) (lua_State *L, const char *s);
Func _lua_stringToNumber($pState, $sString)
	Local $aRet = DllCall($__gLua_hDLL, "ulong_ptr:cdecl", "lua_stringtonumber", "ptr", $pState, "str", $sString)
	If @error Then Return SetError(@error, 0, 0)
	Return $aRet[0]
EndFunc   ;==>_lua_stringToNumber

;~ LUA_API lua_Alloc (lua_getallocf) (lua_State *L, void **ud);
Func _lua_getAllocF($pState)
	Local $aRet = DllCall($__gLua_hDLL, "ptr:cdecl", "lua_getallocf", "ptr", $pState, "ptr*", 0)
	If @error Then Return SetError(@error, 0, Null)
	Return SetError(0, $aRet[2], $aRet[0])
EndFunc   ;==>_lua_getAllocF

;~ LUA_API void (lua_setallocf) (lua_State *L, lua_Alloc f, void *ud);
Func _lua_setAllocF($pState, $pfnAlloc, $pUserData = Null)
	DllCall($__gLua_hDLL, "none:cdecl", "lua_setallocf", "ptr", $pState, "ptr", __lua_helper_regFunc($pfnAlloc, "ptr:cdecl", "ptr;ptr;ulong_ptr;ulong_ptr"), "ptr", $pUserData)
	If @error Then Return SetError(@error, 0, False)
	Return True
EndFunc   ;==>_lua_setAllocF


; ------------------
; some useful macros
; ------------------

; not really needed
;~ #define lua_getextraspace(L)	((void *)((char *)(L) - LUA_EXTRASPACE))

; already defined
;~ #define lua_tonumber(L,i)	lua_tonumberx(L,(i),NULL)
;~ #define lua_tointeger(L,i)	lua_tointegerx(L,(i),NULL)

;~ #define lua_pop(L,n)		lua_settop(L, -(n)-1)
Func _lua_pop($pState, $iN)
	_lua_setTop($pState, (-1 * $iN) - 1)
EndFunc   ;==>_lua_pop

;~ #define lua_newtable(L)		lua_createtable(L, 0, 0)
Func _lua_newTable($pState)
	Local $vRet = _lua_createTable($pState, 0, 0)
	Return SetError(@error, @extended, $vRet)
EndFunc   ;==>_lua_newTable

;~ #define lua_register(L,n,f) (lua_pushcfunction(L, (f)), lua_setglobal(L, (n)))
Func _lua_register($pState, $sName, $pfnCFunction)
	_lua_pushCFunction($pState, $pfnCFunction)
	_lua_setGlobal($pState, $sName)
EndFunc   ;==>_lua_register

;~ #define lua_pushcfunction(L,f)	lua_pushcclosure(L, (f), 0)
Func _lua_pushCFunction($pState, $pfnCFunction)
	_lua_pushCClosure($pState, $pfnCFunction, 0)
EndFunc   ;==>_lua_pushCFunction

;~ #define lua_isfunction(L,n) (lua_type(L, (n)) == LUA_TFUNCTION)
Func _lua_isFunction($pState, $iIdx)
	Return _lua_type($pState, $iIdx) = $LUA_TFUNCTION
EndFunc   ;==>_lua_isFunction

;~ #define lua_istable(L,n)	(lua_type(L, (n)) == LUA_TTABLE)
Func _lua_isTable($pState, $iIdx)
	Return _lua_type($pState, $iIdx) = $LUA_TTABLE
EndFunc   ;==>_lua_isTable

;~ #define lua_islightuserdata(L,n)	(lua_type(L, (n)) == LUA_TLIGHTUSERDATA)
Func _lua_isLightUserdata($pState, $iIdx)
	Return _lua_type($pState, $iIdx) = $LUA_TLIGHTUSERDATA
EndFunc   ;==>_lua_isLightUserdata

;~ #define lua_isnil(L,n) (lua_type(L, (n)) == LUA_TNIL)
Func _lua_isNil($pState, $iIdx)
	Return _lua_type($pState, $iIdx) = $LUA_TNIL
EndFunc   ;==>_lua_isNil

;~ #define lua_isboolean(L,n) (lua_type(L, (n)) == LUA_TBOOLEAN)
Func _lua_isBoolean($pState, $iIdx)
	Return _lua_type($pState, $iIdx) = $LUA_TBOOLEAN
EndFunc   ;==>_lua_isBoolean

;~ #define lua_isthread(L,n) (lua_type(L, (n)) == LUA_TTHREAD)
Func _lua_isThread($pState, $iIdx)
	Return _lua_type($pState, $iIdx) = $LUA_TTHREAD
EndFunc   ;==>_lua_isThread

;~ #define lua_isnone(L,n) (lua_type(L, (n)) == LUA_TNONE)
Func _lua_isNone($pState, $iIdx)
	Return _lua_type($pState, $iIdx) = $LUA_TNONE
EndFunc   ;==>_lua_isNone

;~ #define lua_isnoneornil(L, n) (lua_type(L, (n)) <= 0)
Func _lua_isNoneOrNil($pState, $iIdx)
	Return _lua_type($pState, $iIdx) <= 0
EndFunc   ;==>_lua_isNoneOrNil

; equivalent to lua_pushstring
;~ #define lua_pushliteral(L, s) lua_pushstring(L, "" s)

;~ #define lua_pushglobaltable(L) ((void)lua_rawgeti(L, LUA_REGISTRYINDEX, LUA_RIDX_GLOBALS))
Func _lua_pushGlobalTable($pState)
	_lua_rawGetI($pState, $LUA_REGISTRYINDEX, $LUA_RIDX_GLOBALS)
EndFunc   ;==>_lua_pushGlobalTable

; already implemented
;~ #define lua_tostring(L,i) lua_tolstring(L, (i), NULL)

;~ #define lua_insert(L,idx) lua_rotate(L, (idx), 1)
Func _lua_insert($pState, $iIdx)
	_lua_rotate($pState, $iIdx, 1)
EndFunc   ;==>_lua_insert

;~ #define lua_remove(L,idx) (lua_rotate(L, (idx), -1), lua_pop(L, 1))
Func _lua_remove($pState, $iIdx)
	_lua_rotate($pState, $iIdx, -1)
	_lua_pop($pState, 1)
EndFunc   ;==>_lua_remove

;~ #define lua_replace(L,idx) (lua_copy(L, -1, (idx)), lua_pop(L, 1))
Func _lua_replace($pState, $iIdx)
	_lua_copy($pState, -1, $iIdx)
	_lua_pop($pState, 1)
EndFunc   ;==>_lua_replace

; -------------------------------------------------------------
; Not implemented: compatibility macros for unsigned conversion
;                  debug API
; -------------------------------------------------------------

; =====================================================================================================================
; HEADER: lauxlib.h
; =====================================================================================================================

;~ LUALIB_API void (luaL_checkversion_) (lua_State *L, lua_Number ver, size_t sz);
;~ #define luaL_checkversion(L) luaL_checkversion_(L, LUA_VERSION_NUM, LUAL_NUMSIZES)
Func _luaL_checkversion($pState)
	DllCall($__gLua_hDLL, "none:cdecl", "luaL_checkversion_", "ptr", $pState, "double", $LUA_VERSION_NUM, "ulong_ptr", 8 * 16 + 8) ; LUAL_NUMSIZES
EndFunc   ;==>_luaL_checkversion

;~ LUALIB_API int (luaL_getmetafield) (lua_State *L, int obj, const char *e);
Func _luaL_getMetaField($pState, $iObj, $sField)
	Local $aRet = DllCall($__gLua_hDLL, "int:cdecl", "luaL_getmetafield", "ptr", $pState, "int", $iObj, "str", $sField)
	If @error Then Return SetError(@error, 0, $LUA_TNONE)
	Return $aRet[0]
EndFunc   ;==>_luaL_getMetaField

;~ LUALIB_API int (luaL_callmeta) (lua_State *L, int obj, const char *e);
Func _luaL_callMeta($pState, $iIdxObj, $sFieldName)
	Local $aRet = DllCall($__gLua_hDLL, "int:cdecl", "luaL_callmeta", "ptr", $pState, "int", $iIdxObj, "str", $sFieldName)
	If @error Then Return SetError(@error, 0, False)
	Return $aRet[0] <> 0
EndFunc   ;==>_luaL_callMeta

;~ LUALIB_API const char *(luaL_tolstring) (lua_State *L, int idx, size_t *len);
Func _luaL_toString($pState, $iIdx)
	Local $vRet = _luaL_toBinary($pState, $iIdx)
	SetError(@error, @extended)
	Return BinaryToString($vRet[0], 4)
EndFunc   ;==>_luaL_toString

Func _luaL_toBinary($pState, $iIdx)
	Local $aRet = DllCall($__gLua_hDLL, "ptr:cdecl", "luaL_tolstring", "ptr", $pState, "int", $iIdx, "ulong_ptr*", 0)
	If @error Then Return SetError(@error, 0, Binary(""))
	If $aRet[3] <= 0 Then Return Binary("")
	Return DllStructGetData(DllStructCreate("byte[" & $aRet[3] & "]", $aRet[0]), 1)
EndFunc   ;==>_luaL_toBinary

; INCOMPATIBLE WITH AUTOIT (error raise: setjmp/longjmp)
;~ LUALIB_API int (luaL_argerror) (lua_State *L, int arg, const char *extramsg);
;~ Func _luaL_argError($pState, $iArg, $sExtraMsg)
;~ 	DllCall($__gLua_hDLL, "int:cdecl", "luaL_argerror", "ptr", $pState, "int", $iArg, "str", $sExtraMsg)
;~ EndFunc

; INCOMPATIBLE WITH AUTOIT (error raise: setjmp/longjmp)
;~ LUALIB_API const char *(luaL_checklstring) (lua_State *L, int arg, size_t *l);
;~ Func _luaL_checkString($pState, $iArg)
;~ 	Local $vRet = _luaL_checkBinary($pState, $iArg)
;~ 	SetError(@error, @extended)
;~ 	Return BinaryToString($vRet)
;~ EndFunc
;~ Func _luaL_checkBinary($pState, $iArg)
;~ 	Local $aRet = DllCall($__gLua_hDLL, "ptr:cdecl", "luaL_checklstring", "ptr", $pState, "int", $iArg, "ulong_ptr*", 0)
;~ 	If @error Then Return SetError(@error, 0, Binary(""))
;~ 	Return __lua_helper_ptr2bin($aRet[0], $aRet[3])
;~ EndFunc

;~ LUALIB_API const char *(luaL_optlstring) (lua_State *L, int arg, const char *def, size_t *l);
Func _luaL_optString($pState, $iArg, $sDefault = "")
	If _lua_isNoneOrNil($pState, $iArg) Then
		Return $sDefault
	Else
		Local $vRet = _lua_toString($pState, $iArg)
		Return SetError(@error, @extended, $vRet)
	EndIf
EndFunc   ;==>_luaL_optString
Func _luaL_optBinary($pState, $iArg, $sDefault = Binary(""))
	If _lua_isNoneOrNil($pState, $iArg) Then
		Return $sDefault
	Else
		Local $vRet = _lua_toBinary($pState, $iArg)
		Return SetError(@error, @extended, $vRet)
	EndIf
EndFunc   ;==>_luaL_optBinary

; INCOMPATIBLE WITH AUTOIT (error raise: setjmp/longjmp)
;~ LUALIB_API lua_Number (luaL_checknumber) (lua_State *L, int arg);

;~ LUALIB_API lua_Number (luaL_optnumber) (lua_State *L, int arg, lua_Number def);
Func _luaL_optNumber($pState, $iArg, $fDefault = 0.0)
	Local $aRet = DllCall($__gLua_hDLL, "double:cdecl", "luaL_optnumber", "ptr", $pState, "int", $iArg, "double", $fDefault)
	If @error Then Return SetError(@error, 0, $fDefault)
	Return $aRet[0]
EndFunc   ;==>_luaL_optNumber

; INCOMPATIBLE WITH AUTOIT (error raise: setjmp/longjmp)
;~ LUALIB_API lua_Integer (luaL_checkinteger) (lua_State *L, int arg);

;~ LUALIB_API lua_Integer (luaL_optinteger) (lua_State *L, int arg, lua_Integer def);
Func _luaL_optInteger($pState, $iArg, $iDefault = 0)
	Local $aRet = DllCall($__gLua_hDLL, "int64:cdecl", "luaL_optinteger", "ptr", $pState, "int", $iArg, "int64", $iDefault)
	If @error Then Return SetError(@error, 0, $iDefault)
	Return $aRet[0]
EndFunc   ;==>_luaL_optInteger

; INCOMPATIBLE WITH AUTOIT (error raise: setjmp/longjmp)
;~ LUALIB_API void (luaL_checkstack) (lua_State *L, int sz, const char *msg);
;~ LUALIB_API void (luaL_checktype) (lua_State *L, int arg, int t);
;~ LUALIB_API void (luaL_checkany) (lua_State *L, int arg);

;~ LUALIB_API int (luaL_newmetatable) (lua_State *L, const char *tname);
Func _luaL_newMetaTable($pState, $sTName)
	Local $aRet = DllCall($__gLua_hDLL, "int:cdecl", "luaL_newmetatable", "ptr", $pState, "str", $sTName)
	If @error Then Return SetError(@error, 0, 0)
	Return $aRet[0]
EndFunc   ;==>_luaL_newMetaTable

;~ LUALIB_API void (luaL_setmetatable) (lua_State *L, const char *tname);
Func _luaL_setMetaTable($pState, $sTName)
	DllCall($__gLua_hDLL, "none:cdecl", "luaL_setmetatable", "ptr", $pState, "str", $sTName)
	If @error Then Return SetError(@error, 0, False)
	Return True
EndFunc   ;==>_luaL_setMetaTable

;~ LUALIB_API void *(luaL_testudata) (lua_State *L, int ud, const char *tname);
Func _luaL_testUData($pState, $iArg, $sTName)
	Local $aRet = DllCall($__gLua_hDLL, "ptr:cdecl", "luaL_testudata", "ptr", $pState, "int", $iArg, "str", $sTName)
	If @error Then Return SetError(@error, 0, Null)
	Return $aRet[0]
EndFunc   ;==>_luaL_testUData

; INCOMPATIBLE WITH AUTOIT (error raise: setjmp/longjmp)
;~ LUALIB_API void *(luaL_checkudata) (lua_State *L, int ud, const char *tname);
;~ Func _luaL_checkUData($pState, $iArg, $sTName)
;~ 	Local $aRet = DllCall($__gLua_hDLL, "ptr:cdecl", "luaL_checkudata", "ptr", $pState, "int", $iArg, "str", $sTName)
;~ 	If @error Then Return SetError(@error, 0, Null)
;~ 	Return $aRet[0]
;~ EndFunc

;~ LUALIB_API void (luaL_where) (lua_State *L, int lvl);
Func _luaL_where($pState, $iLvl)
	DllCall($__gLua_hDLL, "none:cdecl", "luaL_where", "ptr", $pState, "int", $iLvl)
	If @error Then Return SetError(@error, 0, False)
	Return True
EndFunc   ;==>_luaL_where

; INCOMPATIBLE WITH AUTOIT (error raise: setjmp/longjmp)
;~ LUALIB_API int (luaL_error) (lua_State *L, const char *fmt, ...);
;~ Func _luaL_error($pState, $sError)
;~ 	DllCall($__gLua_hDLL, "int:cdecl", "luaL_error", "ptr", $pState, "str", $sError)
;~ 	; function never returns
;~ EndFunc   ;==>_luaL_error

; really usefull?
;~ LUALIB_API int (luaL_checkoption) (lua_State *L, int arg, const char *def, const char *const lst[]);
;~ LUALIB_API int (luaL_fileresult) (lua_State *L, int stat, const char *fname);
;~ LUALIB_API int (luaL_execresult) (lua_State *L, int stat);

;~ LUALIB_API int (luaL_ref) (lua_State *L, int t);
Func _luaL_ref($pState, $iIdxTable)
	Local $aRet = DllCall($__gLua_hDLL, "int:cdecl", "luaL_ref", "ptr", $pState, "int", $iIdxTable)
	If @error Then Return SetError(@error, 0, $LUA_NOREF)
	Return $aRet[0]
EndFunc   ;==>_luaL_ref

;~ LUALIB_API void (luaL_unref) (lua_State *L, int t, int ref);
Func _luaL_unref($pState, $iIdxTable, $iRef)
	DllCall($__gLua_hDLL, "none:cdecl", "luaL_unref", "ptr", $pState, "int", $iIdxTable, "int", $iRef)
	If @error Then Return SetError(@error, 0, False)
	Return True
EndFunc   ;==>_luaL_unref

;~ LUALIB_API int (luaL_loadfilex) (lua_State *L, const char *filename, const char *mode);
;~ #define luaL_loadfile(L,f) luaL_loadfilex(L,f,NULL)
Func _luaL_loadFile($pState, $sFilename, $sMode = "bt")
	Local $aRet = DllCall($__gLua_hDLL, "int:cdecl", "luaL_loadfilex", "ptr", $pState, "str", $sFilename, "str", $sMode)
	If @error Then Return SetError(@error, 0, -1)
	Return $aRet[0]
EndFunc   ;==>_luaL_loadFile

;~ LUALIB_API int (luaL_loadbufferx) (lua_State *L, const char *buff, size_t sz, const char *name, const char *mode);
Func _luaL_loadBuffer($pState, $bBuffer, $sName = "", $sMode = "bt")
	If Not IsBinary($bBuffer) Then $bBuffer = StringToBinary($bBuffer, 4)
	Local $iSize = BinaryLen($bBuffer)
	Local $tBuf = DllStructCreate("byte[" & $iSize & "]")
	DllStructSetData($tBuf, 1, $bBuffer)
	Local $aRet = DllCall($__gLua_hDLL, "int:cdecl", "luaL_loadbufferx", "ptr", $pState, "struct*", $tBuf, "ulong_ptr", $iSize, "str", $sName, "str", $sMode)
	If @error Then Return SetError(@error, 0, -1)
	Return $aRet[0]
EndFunc   ;==>_luaL_loadBuffer

;~ LUALIB_API int (luaL_loadstring) (lua_State *L, const char *s);
Func _luaL_loadString($pState, $sString)
	$sString = StringToBinary(String($sString), 4)
	Local $tBuf = DllStructCreate("byte[" & (BinaryLen($sString) + 1) & "]")
	DllStructSetData($tBuf, 1, $sString)
	Local $aRet = DllCall($__gLua_hDLL, "int:cdecl", "luaL_loadstring", "ptr", $pState, "struct*", $tBuf)
	If @error Then Return SetError(@error, 0, -1)
	Return $aRet[0]
EndFunc   ;==>_luaL_loadString

;~ LUALIB_API lua_State *(luaL_newstate) (void);
Func _luaL_newState()
	Local $aRet = DllCall($__gLua_hDLL, "ptr:cdecl", "luaL_newstate")
	If @error Then Return SetError(@error, 0, Null)
	Return $aRet[0]
EndFunc   ;==>_luaL_newState

;~ LUALIB_API lua_Integer (luaL_len) (lua_State *L, int idx);
Func _luaL_len($pState, $iIdx)
	Local $aRet = DllCall($__gLua_hDLL, "int64:cdecl", "luaL_len", "ptr", $pState, "int", $iIdx)
	If @error Then Return SetError(@error, 0, 0)
	Return $aRet[0]
EndFunc   ;==>_luaL_len

;~ LUALIB_API const char *(luaL_gsub) (lua_State *L, const char *s, const char *p, const char *r);
Func _luaL_gsub($pState, $sString, $sP, $sR)
	Local $aRet = DllCall($__gLua_hDLL, "ptr:cdecl", "luaL_gsub", "ptr", $pState, "struct*", __lua_helper_str2buf($sString), "struct*", __lua_helper_str2buf($sP), "struct*", __lua_helper_str2buf($sR))
	If @error Then Return SetError(@error, 0, "")
	Return __lua_helper_ptr2bin($aRet[0])
EndFunc   ;==>_luaL_gsub

;~ LUALIB_API void (luaL_setfuncs) (lua_State *L, const luaL_Reg *l, int nup);
;~ $aFuncs[n][2] = [["funcName", _func|"func"|hReg|pFnc], ...]
Func _luaL_setFuncs($pState, $aFuncs, $iNup = 0)
	Local $tBuf = DllStructCreate("ptr[" & ((UBound($aFuncs) + 1) * 2) & "]")
	Local $x = 1
	For $i = 0 To UBound($aFuncs) - 1
		$aFuncs[$i][0] = __lua_helper_str2buf($aFuncs[$i][0])
		$aFuncs[$i][1] = __lua_helper_regFunc($aFuncs[$i][1], "int:cdecl", "ptr")
		DllStructSetData($tBuf, 1, DllStructGetPtr($aFuncs[$i][0]), $x)
		DllStructSetData($tBuf, 1, $aFuncs[$i][1], $x + 1)
		$x += 2
	Next
	DllCall($__gLua_hDLL, "none:cdecl", "luaL_setfuncs", "ptr", $pState, "struct*", $tBuf, "int", $iNup)
	If @error Then Return SetError(@error, 0, False)
	Return True
EndFunc   ;==>_luaL_setFuncs

;~ LUALIB_API int (luaL_getsubtable) (lua_State *L, int idx, const char *fname);
Func _luaL_getSubTable($pState, $iIdx, $sFName)
	Local $aRet = DllCall($__gLua_hDLL, "int:cdecl", "luaL_getsubtable", "ptr", $pState, "int", $iIdx, "str", $sFName)
	If @error Then Return SetError(@error, 0, False)
	Return $aRet[0]
EndFunc   ;==>_luaL_getSubTable

;~ LUALIB_API void (luaL_traceback) (lua_State *L, lua_State *L1, const char *msg, int level);
Func _luaL_traceBack($pState, $pState1, $sMsg, $iLevel)
	DllCall($__gLua_hDLL, "none:cdecl", "luaL_traceback", "ptr", $pState, "ptr", $pState1, "str", $sMsg, "int", $iLevel)
	If @error Then Return SetError(@error, 0, False)
	Return True
EndFunc   ;==>_luaL_traceBack

;~ LUALIB_API void (luaL_requiref) (lua_State *L, const char *modname, lua_CFunction openf, int glb);
Func _luaL_requiref($pState, $sModName, $pfnOpen, $bGlobal = False)
	DllCall($__gLua_hDLL, "none:cdecl", "luaL_requiref", "ptr", $pState, "str", $sModName, "ptr", __lua_helper_regFunc($pfnOpen, "int:cdecl", "ptr"), "int", $bGlobal)
	If @error Then Return SetError(@error, 0, False)
	Return True
EndFunc   ;==>_luaL_requiref


; ------------------
; Some useful macros
; ------------------

;~ #define luaL_newlibtable(L,l) lua_createtable(L, 0, sizeof(l)/sizeof((l)[0]) - 1)
Func _luaL_newLibTable($pState, ByRef $aFuncs)
	Local $vRet = _lua_createTable($pState, 0, UBound($aFuncs))
	Return SetError(@error, @extended, $vRet)
EndFunc   ;==>_luaL_newLibTable

;~ #define luaL_newlib(L,l) (luaL_checkversion(L), luaL_newlibtable(L,l), luaL_setfuncs(L,l,0))
Func _luaL_newLib($pState, ByRef $aFuncs)
	If Not _luaL_newLibTable($pState, $aFuncs) Then Return SetError(@error, 0, False)
	If Not _luaL_setFuncs($pState, $aFuncs) Then Return SetError(@error, 0, False)
	Return True
EndFunc   ;==>_luaL_newLib

; INCOMPATIBLE WITH AUTOIT (error raise: setjmp/longjmp)
;~ #define luaL_argcheck(L, cond,arg,extramsg) ((void)((cond) || luaL_argerror(L, (arg), (extramsg))))
;~ Func _luaL_argCheck($pState, $bCond, $iArg, $sExtraMsg = "")
;~ 	If Not $bCond Then
;~ 		Local $vRet = _luaL_argError($pState, $iArg, $sExtraMsg)
;~ 		Return SetError(@error, @extended, $vRet) ; anyway, function never returns, and crashes AutoIt interpreter...
;~ 	EndIf
;~ EndFunc

; already implemented
;~ #define luaL_checkstring(L,n)	(luaL_checklstring(L, (n), NULL))
;~ #define luaL_optstring(L,n,d)	(luaL_optlstring(L, (n), (d), NULL))

;~ #define luaL_typename(L,i)	lua_typename(L, lua_type(L,(i)))
Func _luaL_typeName($pState, $iIdx)
	Return _lua_typeName($pState, _lua_type($pState, $iIdx))
EndFunc   ;==>_luaL_typeName

;~ #define luaL_dofile(L, fn) (luaL_loadfile(L, fn) || lua_pcall(L, 0, LUA_MULTRET, 0))
Func _luaL_doFile($pState, $sFilename)
	Local $vRet = _luaL_loadFile($pState, $sFilename)
	If $vRet <> $LUA_OK Then Return SetError(@error ? @error : 1, 0, $vRet)

	$vRet = _lua_pCall($pState, 0, $LUA_MULTRET, 0)
	Return SetError(@error, 0, $vRet)
EndFunc   ;==>_luaL_doFile

;~ #define luaL_dostring(L, s) (luaL_loadstring(L, s) || lua_pcall(L, 0, LUA_MULTRET, 0))
Func _luaL_doString($pState, $sString)
	Local $vRet = _luaL_loadString($pState, $sString)
	If @error Or $vRet <> $LUA_OK Then Return $vRet

	$vRet = _lua_pCall($pState, 0, $LUA_MULTRET, 0)
	Return SetError(@error, @extended, $vRet)
EndFunc   ;==>_luaL_doString

Func _luaL_doBuffer($pState, $bBuffer, $sName = "", $sMode = "bt")
	Local $vRet = _luaL_loadBuffer($pState, $bBuffer, $sName, $sMode)
	If @error Or $vRet <> $LUA_OK Then Return $vRet

	$vRet = _lua_pCall($pState, 0, $LUA_MULTRET, 0)
	Return SetError(@error, @extended, $vRet)
EndFunc   ;==>_luaL_doBuffer

;~ #define luaL_getmetatable(L,n)	(lua_getfield(L, LUA_REGISTRYINDEX, (n)))
Func _luaL_getMetaTable($pState, $sTName)
	Local $vRet = _lua_getField($pState, $LUA_REGISTRYINDEX, $sTName)
	Return SetError(@error, @extended, $vRet)
EndFunc   ;==>_luaL_getMetaTable

; not needed
;~ #define luaL_opt(L,f,n,d)	(lua_isnoneornil(L,(n)) ? (d) : f(L,(n)))

; no need to implement (see _luaL_loadBuffer)
;~ #define luaL_loadbuffer(L,s,sz,n)	luaL_loadbufferx(L,s,sz,n,NULL)


; ----------------------------------------------------------------------------
; Not implemented: generic Buffer manipulation
;                  file handles for IO library
;                  compatibility with old module system
;                  "abstraction Layer" for basic report of messages and errors
;                  compatibility with deprecated conversions
; ----------------------------------------------------------------------------

; =====================================================================================================================
; HEADER: lualib.h
; =====================================================================================================================

;~ /* version suffix for environment variable names */
;~ #define LUA_VERSUFFIX          "_" LUA_VERSION_MAJOR "_" LUA_VERSION_MINOR

;~ LUAMOD_API int (luaopen_base) (lua_State *L);
Func _luaopen_base($pState)
	Local $aRet = DllCall($__gLua_hDLL, "int:cdecl", "luaopen_base", "ptr", $pState)
	If @error Then Return SetError(@error, 0, 0)
	Return $aRet[0]
EndFunc   ;==>_luaopen_base

;~ LUAMOD_API int (luaopen_coroutine) (lua_State *L);
Func _luaopen_coroutine($pState)
	Local $aRet = DllCall($__gLua_hDLL, "int:cdecl", "luaopen_coroutine", "ptr", $pState)
	If @error Then Return SetError(@error, 0, 0)
	Return $aRet[0]
EndFunc   ;==>_luaopen_coroutine

;~ LUAMOD_API int (luaopen_table) (lua_State *L);
Func _luaopen_table($pState)
	Local $aRet = DllCall($__gLua_hDLL, "int:cdecl", "luaopen_table", "ptr", $pState)
	If @error Then Return SetError(@error, 0, 0)
	Return $aRet[0]
EndFunc   ;==>_luaopen_table

;~ LUAMOD_API int (luaopen_io) (lua_State *L);
Func _luaopen_io($pState)
	Local $aRet = DllCall($__gLua_hDLL, "int:cdecl", "luaopen_io", "ptr", $pState)
	If @error Then Return SetError(@error, 0, 0)
	Return $aRet[0]
EndFunc   ;==>_luaopen_io

;~ LUAMOD_API int (luaopen_os) (lua_State *L);
Func _luaopen_os($pState)
	Local $aRet = DllCall($__gLua_hDLL, "int:cdecl", "luaopen_os", "ptr", $pState)
	If @error Then Return SetError(@error, 0, 0)
	Return $aRet[0]
EndFunc   ;==>_luaopen_os

;~ LUAMOD_API int (luaopen_string) (lua_State *L);
Func _luaopen_string($pState)
	Local $aRet = DllCall($__gLua_hDLL, "int:cdecl", "luaopen_string", "ptr", $pState)
	If @error Then Return SetError(@error, 0, 0)
	Return $aRet[0]
EndFunc   ;==>_luaopen_string

;~ LUAMOD_API int (luaopen_utf8) (lua_State *L);
Func _luaopen_utf8($pState)
	Local $aRet = DllCall($__gLua_hDLL, "int:cdecl", "luaopen_utf8", "ptr", $pState)
	If @error Then Return SetError(@error, 0, 0)
	Return $aRet[0]
EndFunc   ;==>_luaopen_utf8

;~ LUAMOD_API int (luaopen_bit32) (lua_State *L);
Func _luaopen_bit32($pState)
	Local $aRet = DllCall($__gLua_hDLL, "int:cdecl", "luaopen_bit32", "ptr", $pState)
	If @error Then Return SetError(@error, 0, 0)
	Return $aRet[0]
EndFunc   ;==>_luaopen_bit32

;~ LUAMOD_API int (luaopen_math) (lua_State *L);
Func _luaopen_math($pState)
	Local $aRet = DllCall($__gLua_hDLL, "int:cdecl", "luaopen_math", "ptr", $pState)
	If @error Then Return SetError(@error, 0, 0)
	Return $aRet[0]
EndFunc   ;==>_luaopen_math

;~ LUAMOD_API int (luaopen_debug) (lua_State *L);
Func _luaopen_debug($pState)
	Local $aRet = DllCall($__gLua_hDLL, "int:cdecl", "luaopen_debug", "ptr", $pState)
	If @error Then Return SetError(@error, 0, 0)
	Return $aRet[0]
EndFunc   ;==>_luaopen_debug

;~ LUAMOD_API int (luaopen_package) (lua_State *L);
Func _luaopen_package($pState)
	Local $aRet = DllCall($__gLua_hDLL, "int:cdecl", "luaopen_package", "ptr", $pState)
	If @error Then Return SetError(@error, 0, 0)
	Return $aRet[0]
EndFunc   ;==>_luaopen_package


;~ LUALIB_API void (luaL_openlibs) (lua_State *L);
Func _luaL_openLibs($pState)
	DllCall($__gLua_hDLL, "none:cdecl", "luaL_openlibs", "ptr", $pState)
	If @error Then Return SetError(@error, 0, False)
	Return True
EndFunc   ;==>_luaL_openLibs


; =====================================================================================================================
; Helper functions
; =====================================================================================================================

Func __lua_helper_str2buf($sString, $bZeroTerminated = True)
	If Not IsBinary($sString) Then $sString = StringToBinary($sString, 4)
	Local $iSize = BinaryLen($sString)
	Local $tBuf = DllStructCreate("byte[" & ($bZeroTerminated ? ($iSize + 1) : $iSize) & "]")
	DllStructSetData($tBuf, 1, $sString)
	Return SetError(0, $iSize, $tBuf)
EndFunc   ;==>__lua_helper_str2buf

Func __lua_helper_ptr2bin($pStr, $iSize = -1)
	If Not $pStr Or $iSize = 0 Then Return ""
	If $iSize < 0 Then $iSize = DllCall("kernel32.dll", "int", "lstrlen", "ptr", $pStr)[0] ; avoid WinAPI.au3 dependancy
	If $iSize <= 0 Then Return ""
	Local $tBuf = DllStructCreate("byte[" & $iSize & "]", $pStr)
	Return DllStructGetData($tBuf, 1)
EndFunc   ;==>__lua_helper_ptr2bin

Func __lua_helper_regFunc($vFunc, $sReturn, $sParams)
	Local Static $oReg = ObjCreate("Scripting.Dictionary")
	Switch VarGetType($vFunc)
		Case "String", "UserFunction"
			$vFunc = IsString($vFunc) ? $vFunc : FuncName($vFunc)
			Local $sKey = $vFunc & "|" & $sReturn & "|" & $sParams
			If $oReg.Exists($sKey) Then
				Return DllCallbackGetPtr($oReg.Item($sKey))
			Else
				Local $hReg = DllCallbackRegister($vFunc, $sReturn, $sParams)
				$oReg.Item($sKey) = $hReg
				Return DllCallbackGetPtr($hReg)
			EndIf
		Case "Int32"
			Return DllCallbackGetPtr($vFunc)
		Case "Ptr"
			Return $vFunc
	EndSwitch
	Return Null
EndFunc   ;==>__lua_helper_regFunc

; =====================================================================================================================
