#SingleInstance, Force ; Forces a single instance of the script. Useful if you edit and re-open your script many times.
#InstallKeybdHook ; Keyboard hook. Higher chances to make it work with your game.
SetKeyDelay, 100, 200 ; High delay to make sure your hotkeys work. You can lower these values as long as they work!

if not A_IsAdmin ; Admin rights checker.
{
   Run *RunAs "%A_ScriptFullPath%"  
   ExitApp
}

f1::
	Loop ; The actual loop. Sends W, waits about 5 seconds, sends S. Should be enough to fool an anti-afk. Customizable, of course.
	{
		SoundBeep
		SoundBeep
		SoundBeep
		Send {w}
		RandSleep(600000,840000)
		SoundBeep
		SoundBeep
		SoundBeep
		Send {s}
		RandSleep(600000,840000)
	}
	Return

f2::Pause ; Pause the script (and resume).


;--V Functions down here V--


RandSleep(x,y) ; Neat function to have random sleep times.
{
	Random, rand, %x%, %y%
	Sleep %rand%
}