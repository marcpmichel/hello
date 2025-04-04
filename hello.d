import core.stdc.stdio;

extern(C) int main() {
	printf("hello %d\n", 1);

	int[3] arr = [1,2,3];
	foreach(v; arr) printf("%d ", v);

	return 0;
}

