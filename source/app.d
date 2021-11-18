/*
import matrix;
import std.stdio : writeln;
import std.process;
import core.thread;
import std.file;
import std.string;
import std.functional;
import std.conv;

MatrixClient mx;
void main()
{
	mx = new MatrixClient("https://ryhn.link");

	mx.login("rbot", environment["PASSWORD"]);

	writeln("Logged in as " ~ mx.user_id);

	//mx.joinRoom("#public:ryhn.link");

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
	mx.sendString(id, "fuck");

	string mxc = mx.uploadFile(read("test.jpeg"), "myfile.jpeg", "image/jpeg");
	mx.sendImage(id,"myfile.jpeg",mxc);
	mx.sendHTML(id, "This is funny <img src=\"%s\"/>".format(mxc));

	mx.inviteDelegate = (&onInvited).toDelegate;
	mx.messageDelegate = (&onMessage).toDelegate;
	while (1)
	{
		mx.sync();
	}
}

void onInvited(string to, string by)
{
	writeln("Invited to %s by %s".format(to, by));
	mx.joinRoom(to);
	mx.sendString(to, "I was invited to join by " ~ by);
}

void onMessage(MatrixMessage msg)
{
	mx.markRead(msg.roomId, msg.eventId);
	if (MatrixTextMessage text = cast(MatrixTextMessage)msg)
	{
		writeln("%s - %s: %s".format(text.roomId, text.author, text.conent));
	}
	else
	{
		writeln("%s - %s of type %s".format(msg.roomId, msg.author, msg.type));
	}
}
*/