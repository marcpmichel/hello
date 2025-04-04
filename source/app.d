import std.stdio;

void main() {
	writeln("hello");
}

int add(int a, int b) {
	return a + b;
}

unittest {
	assert( 3 + 2 == add(3,2) );
}

