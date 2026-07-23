Require pwsh
Require zsh

Output "build/social/terminalslides-social-vhs.mp4"

Set Shell "zsh"
Set Width 1280
Set Height 720
Set FontSize 16
Set FontFamily "Menlo"
Set LineHeight 1.1
Set TypingSpeed 40ms
Set Framerate 30
Set Theme {"name":"Midnight","black":"#07111F","red":"#FF6B6B","green":"#4BFFB5","yellow":"#FFB531","blue":"#31B5FF","magenta":"#B565FF","cyan":"#31B5FF","white":"#E5F1FF","brightBlack":"#6B8FA8","brightRed":"#FF6B6B","brightGreen":"#4BFFB5","brightYellow":"#FFB531","brightBlue":"#31B5FF","brightMagenta":"#B565FF","brightCyan":"#31B5FF","brightWhite":"#E5F1FF","background":"#07111F","foreground":"#E5F1FF","selection":"#B565FF","cursor":"#E5F1FF"}
Set Padding 24
Set Margin 20
Set MarginFill "#07111F"
Set BorderRadius 12

Hide
Type@0ms "export PS1='PS> '; function Start-TerminalSlidesDemo { ./Scripts/show-social-demo; }"
Enter
Sleep 500ms
Ctrl+L
Sleep 500ms

Show
Type "Install-Module TerminalSlides"
Sleep 1800ms
Ctrl+C
Wait+Screen /PS>/
Sleep 300ms
Type "Start-TerminalSlidesDemo"
Enter
Wait+Screen /Slide 1 of 8/
Sleep 1200ms

Right
Sleep 650ms
Right
Sleep 650ms
Right
Sleep 1000ms

PageDown
Wait+Screen /Slide 2 of 8/
Sleep 1800ms

PageDown
Wait+Screen /Slide 3 of 8/
Sleep 1500ms

PageDown
Wait+Screen /Slide 4 of 8/
Sleep 1600ms

PageDown
Wait+Screen /Slide 5 of 8/
Sleep 1600ms

Type "o"
Wait+Screen /TerminalSlides Feature Tour/
Sleep 1800ms

Type "?"
Wait+Screen /TerminalSlides Help/
Sleep 2800ms
