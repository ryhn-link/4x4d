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

	string password = environment["PASSWORD"];
	mx.passwordLogin("rbot", password, "rbot");

	writeln("Logged in as " ~ mx.userId);

	auto p = mx.getProfile("@ryhon:ryhn.link");
	writeln(p.displayName);
	writeln(p.avatarUrl);

	import std.file;
	write("avatar.png",mx.downloadFile(p.avatarUrl));
	write("avatar_thumb.png",mx.downloadThumbnail(p.avatarUrl, 32,32, MatrixResizeMethod.crop, "image/png"));
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
