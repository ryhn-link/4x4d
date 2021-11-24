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

	MatrixEvent e = mx.getEvent(mx.resolveRoomAlias("#testing:ryhn.link"), "$MkiF-WKB7xb-46VjdJESW-9AlW0zpHmUO4HpQUD8aZQ");
	writeln(e.type);

	if(MatrixTextMessage m = cast(MatrixTextMessage) e)
		writeln(m.content);
}

void onEvent(MatrixEvent e)
{
	if (MatrixMessage msg = cast(MatrixTextMessage) e)
	{
		if(msg.content.toLower.indexOf("nice") != -1)
			mx.addReaction(e.roomId, e.eventId, "👌");

		if(msg.msgtype == "m.text")
		{
			string roomid = mx.getOrCreateDirectMessageRoom(e.sender);
			mx.sendString(roomid, "Nice to meet you, " ~ e.sender);
		}
	}
}
