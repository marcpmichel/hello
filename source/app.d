module app;

import std.stdio;
import std.string : format, strip;
import terminal; // Our new module

void main() {
    // Ensure all output is flushed immediately.
    // This is generally good for interactive terminal applications.
    // stdout.settings.autoflush = true;

    // Use scope(exit) to ensure colors are reset and cursor is moved to a clean position.
    // getKeyPress() in terminal.d already handles its own raw mode cleanup.
    scope(exit) {
        resetColors();
        TerminalSize endSize = getTerminalSize();
        if (endSize.rows > 0 && endSize.cols > 0) { // Avoid setting cursor if size is invalid
            setCursorPosition(endSize.rows, 1); // Move to the last line
        }
        writeln("Exiting demo.");
    }
    
    clearScreen(); // Call the new clearScreen function

    writeln("Terminal Module Demonstration");
    writeln("=============================");
    writeln();

    // 1. Terminal Size
    TerminalSize size = getTerminalSize();
    writefln("Terminal size: %s rows, %s cols", size.rows, size.cols);
    writeln();

    // 2. Cursor Movement
    writeln("--- Cursor Movement Demo ---");
    ushort startRow = 3, startCol = 5;
    if (size.rows > startRow + 5 && size.cols > startCol + 20) { // Ensure space for demo
        setCursorPosition(startRow, startCol);
        writefln("Cursor set to %s,%s. Current reported: (%s,%s)", startRow, startCol, getCursorPosition().row, getCursorPosition().col);
        
        saveCursorPosition();
        writefln("Saved cursor position (%s,%s).", getCursorPosition().row, getCursorPosition().col);

        cursorDown(2);
        cursorForward(10);
        writefln("Moved down 2, right 10. Current reported: (%s,%s)", getCursorPosition().row, getCursorPosition().col);
        
        restoreCursorPosition();
        writefln("Restored position. Current reported: (%s,%s)", getCursorPosition().row, getCursorPosition().col);
        writeln();
    } else {
        writeln("Terminal too small for full cursor movement demo.");
    }


    // 3. Color Manipulation
    writeln("--- Color Manipulation Demo ---");
    ushort colorDemoRow = cast(ushort)(size.rows > startRow + 5 ? startRow + 5 : (size.rows > 1 ? size.rows -1 : 1));
    if (size.rows > 1 && size.cols > 1) setCursorPosition(colorDemoRow, 1);

    setForegroundColor256(1); // Xterm Red
    setBackgroundColor256(15); // Xterm Bright White
    writeln("Text in Xterm Red (1) on Bright White (15) (256-color mode)");
    resetColors(); // Reset before next demo line

    if (size.rows > 1 && size.cols > 1) setCursorPosition(cast(ushort)(colorDemoRow + 1), 1);
    setForegroundColorRGB(100, 255, 100); // Light Green
    setBackgroundColorRGB(20, 40, 60);   // Dark Blueish-Gray
    writeln("Text in Light Green on Dark Blueish-Gray (RGB mode)");
    resetColors(); // Reset after demo

    if (size.rows > 1 && size.cols > 1) setCursorPosition(cast(ushort)(colorDemoRow + 2), 1);
    writeln("Colors reset to default for this line.");
    writeln();

    // 4. Key Press Detection
    writeln("--- Key Press Detection Demo ---");
    writeln("Press any key to see its details. Press Escape or 'q' to exit this test (max 15 keys).");
    
    if (size.rows > 1 && size.cols > 1) setCursorPosition(cast(ushort)(colorDemoRow + 5 < size.rows ? colorDemoRow + 5 : size.rows), 1);
    
    for (int i = 0; i < 15; ++i) {
        KeyPress kp = getKeyPress();
        
        string modifierString;
        if (kp.modifiers & KeyModifier.Shift) modifierString ~= "Shift ";
        if (kp.modifiers & KeyModifier.Control) modifierString ~= "Ctrl ";
        if (kp.modifiers & KeyModifier.Alt) modifierString ~= "Alt ";
        if (modifierString.length == 0) modifierString = "None";
        else modifierString = modifierString.strip();

        string keyCharStr;
        if (kp.key == Key.Char && kp.character != '\0') {
             keyCharStr = format("'%c' (ASCII: %d)", kp.character, cast(int)kp.character);
        } else if (kp.character != '\0') { // E.g. Enter might have '\n'
             keyCharStr = format("'%c' (ASCII: %d) (Note: Not Key.Char)", kp.character, cast(int)kp.character);
        }
        else {
            keyCharStr = "N/A";
        }

        writefln("Key: %s, Char: %s, Modifiers: %s", kp.key, keyCharStr, modifierString);

        if (kp.key == Key.Escape || (kp.key == Key.Char && kp.character == 'q')) {
            writeln("Escape or 'q' pressed, exiting key test loop.");
            break;
        }
    }
    writeln();
    
    writeln("Demonstration complete. Resetting and exiting.");
    // The scope(exit) block will handle final cleanup.
}
