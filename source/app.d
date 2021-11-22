import matrix;
import std.stdio : writeln;
import std.process;
import core.thread;
import std.file;
import std.string;
import std.functional;
import std.conv;
import std.json;

MatrixClient mx;
void main()
{
	mx = new MatrixClient("https://ryhn.link");

	mx.login("rbot", environment["PASSWORD"]);
	mx.passwordLogin("rbot", password, "rbot");

	writeln("Logged in as " ~ mx.userId);

	mx.sync();

	mx.eventDelegate = (&onEvent).toDelegate;
	while(1)
	{
		mx.sync();
	}
}

void onEvent(MatrixEvent e)
{
	if (MatrixTextMessage txt = cast(MatrixTextMessage) e)
	{
		if(txt.content.toLower.indexOf("nice") != -1)
			mx.addReaction(e.roomId, e.eventId, "👌");
	}

	if(MatrixReaction r = cast(MatrixReaction) e)
	{
		writeln(r.emoji);
		writeln(r.relatesToEvent);
	}
}
