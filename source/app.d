import std.stdio;
import matrix;
import std.process;

// Test for the library, this will be removed
void main()
{
	auto mx = new MatrixClient("https://ryhn.link");
	mx.login("rbot", environment["PASSWORD"]);

	writeln(mx.user_id);

	foreach (r; mx.getJoinedRooms())
	{
		writeln(r);
	}
}