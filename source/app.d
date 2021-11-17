import matrix;
import std.stdio : writeln;
import std.process;
import core.thread;
import std.file;
import std.string;
import std.functional;
import std.conv;

MatrixClient mx;
// Test for the library, this will be removed
void main()
{
	mx = new MatrixClient("https://ryhn.link");

	if(exists("token"))
	{
		mx.accessToken = readText("token");
		// You probably want to get user info here
	}
	else
	{
		mx.login("rbot", environment["PASSWORD"]);

		write("token", mx.accessToken);
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