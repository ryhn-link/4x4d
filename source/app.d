import std.stdio;
import matrix;
import std.process;
import core.thread;
import std.string;
import std.functional;
import std.conv;

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

	writeln("Logged in as " ~ mx.user_id);

	mx.joinRoom("#public:ryhn.link");

	string[] rms = mx.getJoinedRooms();
	writeln("Joined rooms: " ~ rms.length.to!string);
	foreach (r; rms)
	{
		writeln("-" ~ r);
	}
	
	string id = mx.resolveRoomAlias("#testing:ryhn.link");

	mx.sendHTML(
		id,
		"<b>bois</b>... today we're gonna be uh testing the matrix API");

	mx.sendString(id, "man...");
	Thread.sleep(dur!("seconds")( 3 ));
	mx.sendString(id, "fuck");

	mx.inviteDelegate = (&invited).toDelegate;
	while (1)
	{
		mx.sync();
		writeln("sync");
		Thread.sleep(dur!("seconds")(1));
	}
}

void invited(string to, string by)
{
	writeln("Invited to %s by %s".format(to, by));
	mx.joinRoom(to);
	mx.sendString(to, "I was invited to join by " ~ by);
}