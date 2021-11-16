import std.stdio;
import matrix;
import std.process;
import core.thread;

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

	string id = mx.resolveRoomAlias("#testing:ryhn.link");

	mx.sendHTML(
		id,
		"<b>bois</b>... today we're gonna be uh testing the matrix API");

	mx.sendString(id, "man...");
	Thread.sleep(dur!("seconds")( 3 ));
	mx.sendString(id, "fuck");
}