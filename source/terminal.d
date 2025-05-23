module terminal;

import std.stdio;
import std.math : abs, sqrt; // For RGB to 16 color mapping approximation

struct TerminalSize {
    ushort rows;
    ushort cols;
}

struct CursorPosition {
    ushort row;
    ushort col;
}

// --- Key Input Definitions ---
enum Key {
    Unknown,
    Char, // For printable characters
    Enter, Escape, Backspace, Tab,
    ArrowUp, ArrowDown, ArrowLeft, ArrowRight,
    Home, End, PageUp, PageDown, Insert, Delete,
    F1, F2, F3, F4, F5, F6, F7, F8, F9, F10, F11, F12,
}

enum KeyModifier : ubyte {
    None    = 0,
    Shift   = 1 << 0,
    Control = 1 << 1,
    Alt     = 1 << 2, 
}

struct KeyPress {
    Key key;
    char character; 
    KeyModifier modifiers;
}


version (Posix) {
    import core.sys.posix.sys.ioctl;
    import core.sys.posix.termios;
    import core.sys.posix.unistd; 
    import core.sys.posix.fcntl;  
    import core.stdc.stdio : setvbuf, _IONBF, _IOLBF, _IOFBF; 
    import core.stdc.errno : errno;


} else version (Windows) {
    import core.sys.windows.wincon;
    import core.sys.windows.winbase;
    import core.sys.windows.windef;
    import core.sys.windows.winuser; 

    private WORD defaultConsoleAttributes = 0;
    private bool defaultConsoleAttributesCaptured = false;
    private enum INVALID_COLOR_MAP = ushort.max;

    private WORD mapXterm256ToWindows16(ubyte index) {
        final switch (index) {
            case 0: return 0;                                  
            case 1: return FOREGROUND_RED;                     
            case 2: return FOREGROUND_GREEN;                   
            case 3: return FOREGROUND_RED | FOREGROUND_GREEN;  
            case 4: return FOREGROUND_BLUE;                    
            case 5: return FOREGROUND_RED | FOREGROUND_BLUE;   
            case 6: return FOREGROUND_GREEN | FOREGROUND_BLUE; 
            case 7: return FOREGROUND_RED | FOREGROUND_GREEN | FOREGROUND_BLUE; 
            case 8:  return FOREGROUND_INTENSITY;                                  
            case 9:  return FOREGROUND_RED | FOREGROUND_INTENSITY;                     
            case 10: return FOREGROUND_GREEN | FOREGROUND_INTENSITY;                   
            case 11: return FOREGROUND_RED | FOREGROUND_GREEN | FOREGROUND_INTENSITY;  
            case 12: return FOREGROUND_BLUE | FOREGROUND_INTENSITY;                    
            case 13: return FOREGROUND_RED | FOREGROUND_BLUE | FOREGROUND_INTENSITY;   
            case 14: return FOREGROUND_GREEN | FOREGROUND_BLUE | FOREGROUND_INTENSITY; 
            case 15: return FOREGROUND_RED | FOREGROUND_GREEN | FOREGROUND_BLUE | FOREGROUND_INTENSITY; 
            default:
                stderr.writeln("Warning: Xterm color index ", index, " is not supported on Windows. Color not changed.");
                return INVALID_COLOR_MAP;
        }
    }

    private WORD mapRGBToWindows16(ubyte r, ubyte g, ubyte b) {
        if (r == g && g == b) {
            if (r < 64) return 0; 
            if (r < 192) return FOREGROUND_INTENSITY; 
            return FOREGROUND_RED | FOREGROUND_GREEN | FOREGROUND_BLUE; 
        }
        WORD color = 0;
        bool intensity = (r > 128 || g > 128 || b > 128); 
        if (r > g && r > b) color = FOREGROUND_RED;
        else if (g > r && g > b) color = FOREGROUND_GREEN;
        else if (b > r && b > g) color = FOREGROUND_BLUE;
        else if (r > 100 && g > 100 && b < 50) color = FOREGROUND_RED | FOREGROUND_GREEN; 
        else if (r > 100 && b > 100 && g < 50) color = FOREGROUND_RED | FOREGROUND_BLUE; 
        else if (g > 100 && b > 100 && r < 50) color = FOREGROUND_GREEN | FOREGROUND_BLUE; 
        else color = FOREGROUND_RED | FOREGROUND_GREEN | FOREGROUND_BLUE; 
        if (intensity && color != 0) { 
            bool isAlreadyBright = (color & (FOREGROUND_RED|FOREGROUND_GREEN|FOREGROUND_BLUE)) != 0 && (r > 200 || g > 200 || b > 200);
            if (isAlreadyBright || (r + g + b > 384)) 
                color |= FOREGROUND_INTENSITY;
        }
        if (r < 64 && g < 64 && b < 64) {
            if (r < 32 && g < 32 && b < 32) return 0; 
            return FOREGROUND_INTENSITY; 
        }
        return color;
    }

    private void captureDefaultConsoleAttributes() {
        if (!defaultConsoleAttributesCaptured) {
            HANDLE stdoutHandle = GetStdHandle(STD_OUTPUT_HANDLE);
            if (stdoutHandle != INVALID_HANDLE_VALUE) {
                CONSOLE_SCREEN_BUFFER_INFO csbi;
                if (GetConsoleScreenBufferInfo(stdoutHandle, &csbi)) {
                    defaultConsoleAttributes = csbi.wAttributes;
                    defaultConsoleAttributesCaptured = true;
                } else {
                    defaultConsoleAttributes = FOREGROUND_RED | FOREGROUND_GREEN | FOREGROUND_BLUE; 
                    defaultConsoleAttributesCaptured = true; 
                }
            } else {
                defaultConsoleAttributes = FOREGROUND_RED | FOREGROUND_GREEN | FOREGROUND_BLUE; 
                defaultConsoleAttributesCaptured = true; 
            }
        }
    }
}

// --- Screen Manipulation ---
public void clearScreen() {
    version (Posix) {
        if (!isatty(STDOUT_FILENO)) return;
        writef("\033[2J\033[H"); // Clear screen and move cursor to home
        stdout.flush();
    }
    else version (Windows) {
        HANDLE hConsole = GetStdHandle(STD_OUTPUT_HANDLE);
        if (hConsole == INVALID_HANDLE_VALUE) return;

        CONSOLE_SCREEN_BUFFER_INFO csbi;
        if (!GetConsoleScreenBufferInfo(hConsole, &csbi)) return;

        DWORD consoleSize = csbi.dwSize.X * csbi.dwSize.Y;
        COORD coordScreen = { 0, 0 }; // Top-left corner
        DWORD charsWritten;

        // Fill the entire screen with spaces
        if (!FillConsoleOutputCharacterA(hConsole, ' ', consoleSize, coordScreen, &charsWritten)) return;

        // Get the current attributes and fill the entire screen with them
        if (!FillConsoleOutputAttribute(hConsole, csbi.wAttributes, consoleSize, coordScreen, &charsWritten)) return;

        // Move the cursor to the top-left corner
        SetConsoleCursorPosition(hConsole, coordScreen);
    }
    else {
        // Unsupported platform
    }
}


TerminalSize getTerminalSize() {
    version (Posix) {
        if (!isatty(STDOUT_FILENO)) return TerminalSize(0,0); 
        winsize ws;
        if (ioctl(STDOUT_FILENO, TIOCGWINSZ, &ws) == -1) {
            return TerminalSize(0, 0);
        }
        return TerminalSize(ws.ws_row, ws.ws_col);
    }
    else version (Windows) {
        HANDLE stdoutHandle = GetStdHandle(STD_OUTPUT_HANDLE);
        if (stdoutHandle == INVALID_HANDLE_VALUE) {
            return TerminalSize(0, 0);
        }
        CONSOLE_SCREEN_BUFFER_INFO csbi;
        if (!GetConsoleScreenBufferInfo(stdoutHandle, &csbi)) {
            return TerminalSize(0, 0);
        }
        return TerminalSize(cast(ushort)(csbi.srWindow.Bottom - csbi.srWindow.Top + 1), cast(ushort)(csbi.srWindow.Right - csbi.srWindow.Left + 1));
    }
    else {
        return TerminalSize(0, 0); 
    }
}

version (Windows) {
    private COORD savedCursorPosition;
    private bool savedCursorPositionInitialized = false;
}

void setCursorPosition(ushort row, ushort col) {
    version (Posix) {
        if (!isatty(STDOUT_FILENO)) return;
        // ANSI positions are 1-based, row and col are already 1-based
        writef("\033[%d;%dH", row, col);
        stdout.flush();
    }
    else version (Windows) {
        HANDLE stdoutHandle = GetStdHandle(STD_OUTPUT_HANDLE);
        if (stdoutHandle == INVALID_HANDLE_VALUE) {
            return; 
        }
        // Windows API COORD is 0-based
        COORD coord = { cast(short)(col - 1), cast(short)(row - 1) };
        SetConsoleCursorPosition(stdoutHandle, coord);
    }
    else {
        // Unsupported platform
    }
}

void cursorUp(ushort count = 1) {
    version (Posix) {
        if (!isatty(STDOUT_FILENO)) return;
        writef("\033[%dA", count);
        stdout.flush();
    }
    else version (Windows) {
        HANDLE stdoutHandle = GetStdHandle(STD_OUTPUT_HANDLE);
        if (stdoutHandle == INVALID_HANDLE_VALUE) return;
        CONSOLE_SCREEN_BUFFER_INFO csbi;
        if (!GetConsoleScreenBufferInfo(stdoutHandle, &csbi)) return;
        COORD newPos = csbi.dwCursorPosition;
        newPos.Y = cast(short)(newPos.Y - count);
        if (newPos.Y < 0) newPos.Y = 0;
        SetConsoleCursorPosition(stdoutHandle, newPos);
    }
    else {
        // Unsupported platform
    }
}

void cursorDown(ushort count = 1) {
    version (Posix) {
        if (!isatty(STDOUT_FILENO)) return;
        writef("\033[%dB", count);
        stdout.flush();
    }
    else version (Windows) {
        HANDLE stdoutHandle = GetStdHandle(STD_OUTPUT_HANDLE);
        if (stdoutHandle == INVALID_HANDLE_VALUE) return;
        CONSOLE_SCREEN_BUFFER_INFO csbi;
        if (!GetConsoleScreenBufferInfo(stdoutHandle, &csbi)) return;
        COORD newPos = csbi.dwCursorPosition;
        newPos.Y = cast(short)(newPos.Y + count);
        SetConsoleCursorPosition(stdoutHandle, newPos);
    }
    else {
        // Unsupported platform
    }
}

void cursorForward(ushort count = 1) {
    version (Posix) {
        if (!isatty(STDOUT_FILENO)) return;
        writef("\033[%dC", count);
        stdout.flush();
    }
    else version (Windows) {
        HANDLE stdoutHandle = GetStdHandle(STD_OUTPUT_HANDLE);
        if (stdoutHandle == INVALID_HANDLE_VALUE) return;
        CONSOLE_SCREEN_BUFFER_INFO csbi;
        if (!GetConsoleScreenBufferInfo(stdoutHandle, &csbi)) return;
        COORD newPos = csbi.dwCursorPosition;
        newPos.X = cast(short)(newPos.X + count);
        SetConsoleCursorPosition(stdoutHandle, newPos);
    }
    else {
        // Unsupported platform
    }
}

void cursorBackward(ushort count = 1) {
    version (Posix) {
        if (!isatty(STDOUT_FILENO)) return;
        writef("\033[%dD", count);
        stdout.flush();
    }
    else version (Windows) {
        HANDLE stdoutHandle = GetStdHandle(STD_OUTPUT_HANDLE);
        if (stdoutHandle == INVALID_HANDLE_VALUE) return;
        CONSOLE_SCREEN_BUFFER_INFO csbi;
        if (!GetConsoleScreenBufferInfo(stdoutHandle, &csbi)) return;
        COORD newPos = csbi.dwCursorPosition;
        newPos.X = cast(short)(newPos.X - count);
        if (newPos.X < 0) newPos.X = 0;
        SetConsoleCursorPosition(stdoutHandle, newPos);
    }
    else {
        // Unsupported platform
    }
}

void saveCursorPosition() {
    version (Posix) {
        if (!isatty(STDOUT_FILENO)) return;
        writef("\033[s");
        stdout.flush();
    }
    else version (Windows) {
        HANDLE stdoutHandle = GetStdHandle(STD_OUTPUT_HANDLE);
        if (stdoutHandle == INVALID_HANDLE_VALUE) return;
        CONSOLE_SCREEN_BUFFER_INFO csbi;
        if (!GetConsoleScreenBufferInfo(stdoutHandle, &csbi)) return;
        savedCursorPosition = csbi.dwCursorPosition;
        savedCursorPositionInitialized = true;
    }
    else {
        // Unsupported platform
    }
}

void restoreCursorPosition() {
    version (Posix) {
        if (!isatty(STDOUT_FILENO)) return;
        writef("\033[u");
        stdout.flush();
    }
    else version (Windows) {
        if (!savedCursorPositionInitialized) return; 
        HANDLE stdoutHandle = GetStdHandle(STD_OUTPUT_HANDLE);
        if (stdoutHandle == INVALID_HANDLE_VALUE) return;
        SetConsoleCursorPosition(stdoutHandle, savedCursorPosition);
    }
    else {
        // Unsupported platform
    }
}

CursorPosition getCursorPosition() {
    version (Posix) {
        if (!isatty(STDIN_FILENO) || !isatty(STDOUT_FILENO)) {
            return CursorPosition(0, 0);
        }
        termios originalTerm, rawTerm;
        if (tcgetattr(STDIN_FILENO, &originalTerm) == -1) {
            return CursorPosition(0, 0);
        }
        rawTerm = originalTerm;
        rawTerm.c_iflag &= ~(IGNBRK | BRKINT | PARMRK | ISTRIP | INLCR | IGNCR | ICRNL | IXON);
        rawTerm.c_oflag &= ~OPOST;
        rawTerm.c_lflag &= ~(ECHO | ECHONL | ICANON | ISIG | IEXTEN);
        rawTerm.c_cflag &= ~(CSIZE | PARENB);
        rawTerm.c_cflag |= CS8;
        rawTerm.c_cc[VMIN] = 1; 
        rawTerm.c_cc[VTIME] = 1; 
        if (tcsetattr(STDIN_FILENO, TCSADRAIN, &rawTerm) == -1) {
            return CursorPosition(0, 0);
        }
        scope(exit) { 
            tcsetattr(STDIN_FILENO, TCSADRAIN, &originalTerm);
        }
        writef("\033[6n");
        stdout.flush();
        char[32] buf = void; 
        size_t bytesRead = 0;
        char c;
        while (bytesRead < buf.length -1) { 
            ssize_t n = read(STDIN_FILENO, &c, 1);
            if (n > 0) {
                buf[bytesRead++] = c;
                if (c == 'R') break;
            } else if (n == 0) { 
                return CursorPosition(0,0); 
            } else { 
                return CursorPosition(0,0);
            }
        }
        buf[bytesRead] = '\0'; 
        ushort r, co;
        import std.conv : to;
        char* responseStr = buf.ptr;
        if (bytesRead < 5 || responseStr[0] != '\033' || responseStr[1] != '[') {
            return CursorPosition(0, 0);
        }
        int semiColonIndex = -1;
        for(int i = 2; i < bytesRead -1; ++i) {
            if(responseStr[i] == ';') {
                semiColonIndex = i;
                break;
            }
        }
        if (semiColonIndex == -1 || responseStr[bytesRead-1] != 'R') {
            return CursorPosition(0,0); 
        }
        try {
            r = to!ushort(responseStr[2 .. semiColonIndex]);
            co = to!ushort(responseStr[semiColonIndex + 1 .. bytesRead -1]);
            return CursorPosition(r, co);
        } catch (Exception e) {
            return CursorPosition(0, 0);
        }
    }
    else version (Windows) {
        HANDLE stdoutHandle = GetStdHandle(STD_OUTPUT_HANDLE);
        if (stdoutHandle == INVALID_HANDLE_VALUE) {
            return CursorPosition(0, 0);
        }
        CONSOLE_SCREEN_BUFFER_INFO csbi;
        if (!GetConsoleScreenBufferInfo(stdoutHandle, &csbi)) {
            return CursorPosition(0, 0);
        }
        return CursorPosition(cast(ushort)(csbi.dwCursorPosition.Y + 1), cast(ushort)(csbi.dwCursorPosition.X + 1));
    }
    else {
        return CursorPosition(0, 0);
    }
}

// --- Color Manipulation Functions ---

void setForegroundColor256(ubyte colorIndex) {
    version (Posix) {
        if (!isatty(STDOUT_FILENO)) return;
        writef("\033[38;5;%dm", colorIndex);
        stdout.flush();
    }
    else version (Windows) {
        captureDefaultConsoleAttributes(); 
        WORD winColor = mapXterm256ToWindows16(colorIndex);
        if (winColor == INVALID_COLOR_MAP) {
            return; 
        }
        HANDLE stdoutHandle = GetStdHandle(STD_OUTPUT_HANDLE);
        if (stdoutHandle == INVALID_HANDLE_VALUE) return;
        CONSOLE_SCREEN_BUFFER_INFO csbi;
        if (!GetConsoleScreenBufferInfo(stdoutHandle, &csbi)) return;
        WORD newAttributes = csbi.wAttributes;
        newAttributes &= ~(FOREGROUND_BLUE | FOREGROUND_GREEN | FOREGROUND_RED | FOREGROUND_INTENSITY); 
        newAttributes |= winColor; 
        SetConsoleTextAttribute(stdoutHandle, newAttributes);
    }
    else {
        // Unsupported platform
    }
}

void setBackgroundColor256(ubyte colorIndex) {
    version (Posix) {
        if (!isatty(STDOUT_FILENO)) return;
        writef("\033[48;5;%dm", colorIndex);
        stdout.flush();
    }
    else version (Windows) {
        captureDefaultConsoleAttributes();
        WORD winColor = mapXterm256ToWindows16(colorIndex); 
        if (winColor == INVALID_COLOR_MAP) {
            return;
        }
        WORD bgWinColor = 0;
        if (winColor & FOREGROUND_RED) bgWinColor |= BACKGROUND_RED;
        if (winColor & FOREGROUND_GREEN) bgWinColor |= BACKGROUND_GREEN;
        if (winColor & FOREGROUND_BLUE) bgWinColor |= BACKGROUND_BLUE;
        if (winColor & FOREGROUND_INTENSITY) bgWinColor |= BACKGROUND_INTENSITY;
        HANDLE stdoutHandle = GetStdHandle(STD_OUTPUT_HANDLE);
        if (stdoutHandle == INVALID_HANDLE_VALUE) return;
        CONSOLE_SCREEN_BUFFER_INFO csbi;
        if (!GetConsoleScreenBufferInfo(stdoutHandle, &csbi)) return;
        WORD newAttributes = csbi.wAttributes;
        newAttributes &= ~(BACKGROUND_BLUE | BACKGROUND_GREEN | BACKGROUND_RED | BACKGROUND_INTENSITY); 
        newAttributes |= bgWinColor; 
        SetConsoleTextAttribute(stdoutHandle, newAttributes);
    }
    else {
        // Unsupported platform
    }
}

void setForegroundColorRGB(ubyte r, ubyte g, ubyte b) {
    version (Posix) {
        if (!isatty(STDOUT_FILENO)) return;
        writef("\033[38;2;%d;%d;%dm", r, g, b);
        stdout.flush();
    }
    else version (Windows) {
        captureDefaultConsoleAttributes();
        WORD winColor = mapRGBToWindows16(r, g, b);
        HANDLE stdoutHandle = GetStdHandle(STD_OUTPUT_HANDLE);
        if (stdoutHandle == INVALID_HANDLE_VALUE) return;
        CONSOLE_SCREEN_BUFFER_INFO csbi;
        if (!GetConsoleScreenBufferInfo(stdoutHandle, &csbi)) return;
        WORD newAttributes = csbi.wAttributes;
        newAttributes &= ~(FOREGROUND_BLUE | FOREGROUND_GREEN | FOREGROUND_RED | FOREGROUND_INTENSITY);
        newAttributes |= winColor;
        SetConsoleTextAttribute(stdoutHandle, newAttributes);
    }
    else {
        // Unsupported platform
    }
}

void setBackgroundColorRGB(ubyte r, ubyte g, ubyte b) {
    version (Posix) {
        if (!isatty(STDOUT_FILENO)) return;
        writef("\033[48;2;%d;%d;%dm", r, g, b);
        stdout.flush();
    }
    else version (Windows) {
        captureDefaultConsoleAttributes();
        WORD winColor = mapRGBToWindows16(r, g, b); 
        WORD bgWinColor = 0;
        if (winColor & FOREGROUND_RED) bgWinColor |= BACKGROUND_RED;
        if (winColor & FOREGROUND_GREEN) bgWinColor |= BACKGROUND_GREEN;
        if (winColor & FOREGROUND_BLUE) bgWinColor |= BACKGROUND_BLUE;
        if (winColor & FOREGROUND_INTENSITY) bgWinColor |= BACKGROUND_INTENSITY;
        HANDLE stdoutHandle = GetStdHandle(STD_OUTPUT_HANDLE);
        if (stdoutHandle == INVALID_HANDLE_VALUE) return;
        CONSOLE_SCREEN_BUFFER_INFO csbi;
        if (!GetConsoleScreenBufferInfo(stdoutHandle, &csbi)) return;
        WORD newAttributes = csbi.wAttributes;
        newAttributes &= ~(BACKGROUND_BLUE | BACKGROUND_GREEN | BACKGROUND_RED | BACKGROUND_INTENSITY);
        newAttributes |= bgWinColor;
        SetConsoleTextAttribute(stdoutHandle, newAttributes);
    }
    else {
        // Unsupported platform
    }
}

void resetColors() {
    version (Posix) {
        if (!isatty(STDOUT_FILENO)) return;
        writef("\033[0m"); 
        stdout.flush();
    }
    else version (Windows) {
        captureDefaultConsoleAttributes(); 
        HANDLE stdoutHandle = GetStdHandle(STD_OUTPUT_HANDLE);
        if (stdoutHandle == INVALID_HANDLE_VALUE) return;
        SetConsoleTextAttribute(stdoutHandle, defaultConsoleAttributes);
    }
    else {
        // Unsupported platform
    }
}


// --- Key Input Function ---
public KeyPress getKeyPress() {
    version (Posix) {
        if (!isatty(STDIN_FILENO)) {
            return KeyPress(Key.Unknown, '\0', KeyModifier.None);
        }

        termios originalTerm, rawTerm;
        if (tcgetattr(STDIN_FILENO, &originalTerm) == -1) {
            return KeyPress(Key.Unknown, '\0', KeyModifier.None);
        }

        rawTerm = originalTerm;
        rawTerm.c_iflag &= ~(IGNBRK | BRKINT | PARMRK | ISTRIP | INLCR | IGNCR | ICRNL | IXON);
        rawTerm.c_oflag &= ~OPOST;
        rawTerm.c_lflag &= ~(ECHO | ECHONL | ICANON | ISIG | IEXTEN);
        rawTerm.c_cflag &= ~(CSIZE | PARENB);
        rawTerm.c_cflag |= CS8;
        rawTerm.c_cc[VMIN] = 1;  
        rawTerm.c_cc[VTIME] = 0; 

        if (tcsetattr(STDIN_FILENO, TCSADRAIN, &rawTerm) == -1) {
            return KeyPress(Key.Unknown, '\0', KeyModifier.None);
        }

        scope(exit) {
            tcsetattr(STDIN_FILENO, TCSADRAIN, &originalTerm);
        }

        ubyte[6] seqBuf; 
        ssize_t nread;
        
        nread = read(STDIN_FILENO, seqBuf.ptr, 1);
        if (nread <= 0) { return KeyPress(Key.Unknown, '\0', KeyModifier.None); } 

        KeyPress press;
        press.modifiers = KeyModifier.None;

        if (seqBuf[0] == 0x1B) { 
            int oldFlags = fcntl(STDIN_FILENO, F_GETFL, 0);
            fcntl(STDIN_FILENO, F_SETFL, oldFlags | O_NONBLOCK);
            ssize_t nextNread = read(STDIN_FILENO, seqBuf.ptr + 1, seqBuf.length - 1);
            fcntl(STDIN_FILENO, F_SETFL, oldFlags);

            if (nextNread <= 0) { 
                press.key = Key.Escape;
                return press;
            }
            size_t seqLen = 1 + nextNread;

            if (seqBuf[1] == '[') { 
                if (seqLen == 3) { 
                    final switch(seqBuf[2]) {
                        case 'A': press.key = Key.ArrowUp; return press;
                        case 'B': press.key = Key.ArrowDown; return press;
                        case 'C': press.key = Key.ArrowRight; return press;
                        case 'D': press.key = Key.ArrowLeft; return press;
                        case 'H': press.key = Key.Home; return press;
                        case 'F': press.key = Key.End; return press; 
                        default: break; 
                    }
                } else if (seqBuf[seqLen - 1] == '~') { 
                    ubyte param1 = 0;
                    int paramStart = 2;
                    int paramEnd = cast(int)seqLen - 2;
                    if (paramStart <= paramEnd) {
                        string numStr;
                        for (int i = paramStart; i <= paramEnd; i++) {
                            if (seqBuf[i] >= '0' && seqBuf[i] <= '9') {
                                numStr ~= cast(char)seqBuf[i];
                            } else { 
                                numStr = ""; 
                                break;
                            }
                        }
                        if (numStr.length > 0) {
                             import std.conv : to;
                             try { param1 = to!ubyte(numStr); } catch (Exception e) { }
                        }
                    }
                    final switch (param1) {
                        case 1: press.key = Key.Home; return press; 
                        case 2: press.key = Key.Insert; return press;
                        case 3: press.key = Key.Delete; return press;
                        case 4: press.key = Key.End; return press;    
                        case 5: press.key = Key.PageUp; return press;
                        case 6: press.key = Key.PageDown; return press;
                        case 11: press.key = Key.F1; return press; 
                        case 12: press.key = Key.F2; return press;
                        case 13: press.key = Key.F3; return press;
                        case 14: press.key = Key.F4; return press;
                        case 15: press.key = Key.F5; return press; 
                        case 17: press.key = Key.F6; return press; 
                        case 18: press.key = Key.F7; return press;
                        case 19: press.key = Key.F8; return press;
                        case 20: press.key = Key.F9; return press;
                        case 21: press.key = Key.F10; return press;
                        case 23: press.key = Key.F11; return press;
                        case 24: press.key = Key.F12; return press;
                        default: break;
                    }
                }
                press.key = Key.Unknown; 
                return press;

            } else if (seqBuf[1] == 'O') { 
                 if (seqLen == 3) {
                    final switch(seqBuf[2]) {
                        case 'P': press.key = Key.F1; return press;
                        case 'Q': press.key = Key.F2; return press;
                        case 'R': press.key = Key.F3; return press;
                        case 'S': press.key = Key.F4; return press;
                        default: break;
                    }
                }
                 press.key = Key.Unknown; return press; 
            } else { 
                press.key = Key.Char;
                press.character = cast(char)seqBuf[1];
                press.modifiers = KeyModifier.Alt;
                if (seqBuf[1] > 0 && seqBuf[1] < 0x1B && seqBuf[1] != '\t' && seqBuf[1] != '\n' && seqBuf[1] != '\r') {
                     press.modifiers |= KeyModifier.Control;
                     if (seqBuf[1] >= 1 && seqBuf[1] <= 26) {
                         press.character = cast(char)('a' + seqBuf[1] - 1);
                     }
                }
                return press;
            }
        } else { 
            press.character = cast(char)seqBuf[0];
            if (seqBuf[0] == '\r' || seqBuf[0] == '\n') { 
                press.key = Key.Enter;
                press.character = '\n'; 
            } else if (seqBuf[0] == 0x7F || seqBuf[0] == 0x08) { 
                press.key = Key.Backspace;
            } else if (seqBuf[0] == '\t') { 
                press.key = Key.Tab;
            } else if (seqBuf[0] > 0 && seqBuf[0] < 0x1B) { 
                press.key = Key.Char; 
                press.modifiers = KeyModifier.Control;
                press.character = cast(char)('a' + seqBuf[0] - 1);
            } else if (seqBuf[0] >= 0x20 && seqBuf[0] <= 0x7E) { 
                press.key = Key.Char;
            } else { 
                press.key = Key.Unknown;
            }
            return press;
        }
        return KeyPress(Key.Unknown, '\0', KeyModifier.None);

    } 
    else version (Windows) {
        HANDLE hStdin = GetStdHandle(STD_INPUT_HANDLE);
        if (hStdin == INVALID_HANDLE_VALUE) {
            return KeyPress(Key.Unknown, '\0', KeyModifier.None);
        }

        INPUT_RECORD ir;
        DWORD numRead;

        while (true) {
            if (!ReadConsoleInputW(hStdin, &ir, 1, &numRead) || numRead == 0) {
                return KeyPress(Key.Unknown, '\0', KeyModifier.None);
            }

            if (ir.EventType == KEY_EVENT && ir.Event.KeyEvent.bKeyDown) {
                KeyPress press;
                KEY_EVENT_RECORD ker = ir.Event.KeyEvent;
                
                press.character = ker.uChar.UnicodeChar;
                press.modifiers = KeyModifier.None;

                if (ker.dwControlKeyState & (LEFT_CTRL_PRESSED | RIGHT_CTRL_PRESSED)) {
                    press.modifiers |= KeyModifier.Control;
                }
                if (ker.dwControlKeyState & (LEFT_ALT_PRESSED | RIGHT_ALT_PRESSED)) {
                    press.modifiers |= KeyModifier.Alt;
                }
                if (ker.dwControlKeyState & SHIFT_PRESSED) {
                    press.modifiers |= KeyModifier.Shift;
                }

                final switch (ker.wVirtualKeyCode) {
                    case VK_RETURN: press.key = Key.Enter; press.character = '\n'; break;
                    case VK_ESCAPE: press.key = Key.Escape; break;
                    case VK_BACK:   press.key = Key.Backspace; break;
                    case VK_TAB:    press.key = Key.Tab; break;
                    
                    case VK_UP:     press.key = Key.ArrowUp; break;
                    case VK_DOWN:   press.key = Key.ArrowDown; break;
                    case VK_LEFT:   press.key = Key.ArrowLeft; break;
                    case VK_RIGHT:  press.key = Key.ArrowRight; break;
                    
                    case VK_HOME:   press.key = Key.Home; break;
                    case VK_END:    press.key = Key.End; break;
                    case VK_PRIOR:  press.key = Key.PageUp; break; 
                    case VK_NEXT:   press.key = Key.PageDown; break; 
                    case VK_INSERT: press.key = Key.Insert; break;
                    case VK_DELETE: press.key = Key.Delete; break;

                    case VK_F1:  press.key = Key.F1; break;
                    case VK_F2:  press.key = Key.F2; break;
                    case VK_F3:  press.key = Key.F3; break;
                    case VK_F4:  press.key = Key.F4; break;
                    case VK_F5:  press.key = Key.F5; break;
                    case VK_F6:  press.key = Key.F6; break;
                    case VK_F7:  press.key = Key.F7; break;
                    case VK_F8:  press.key = Key.F8; break;
                    case VK_F9:  press.key = Key.F9; break;
                    case VK_F10: press.key = Key.F10; break;
                    case VK_F11: press.key = Key.F11; break;
                    case VK_F12: press.key = Key.F12; break;
                    
                    default:
                        if (press.character != '\0') { 
                            if ((press.modifiers & KeyModifier.Control) && 
                                (press.character > 0 && press.character <= 0x1A) &&
                                !(ker.wVirtualKeyCode >= VK_F1 && ker.wVirtualKeyCode <= VK_F12) && 
                                !(ker.wVirtualKeyCode >= VK_PRIOR && ker.wVirtualKeyCode <= VK_DOWN) && 
                                 ker.wVirtualKeyCode >= 0x41 && ker.wVirtualKeyCode <= 0x5A) { 
                                press.key = Key.Char;
                                press.character = cast(char)(ker.wVirtualKeyCode - 'A' + 'a'); 
                            } else if (press.character >= ' ') { 
                                press.key = Key.Char;
                            } else { 
                                press.key = Key.Unknown;
                            }
                        } else { 
                            press.key = Key.Unknown;
                        }
                        break;
                }
                
                if (press.key != Key.Unknown || 
                    (press.key == Key.Char && press.character != '\0')) { 
                    return press;
                }
                if (press.key == Key.Char && press.character == '\0' && ker.wVirtualKeyCode != 0) {
                } else if (press.key != Key.Unknown) { 
                    return press;
                }
            } 
        } 
    } 
    else {
        return KeyPress(Key.Unknown, '\0', KeyModifier.None);
    }
}
