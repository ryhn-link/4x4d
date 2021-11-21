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
	mx.passwordLogin("rbot", password, "rbot");

	writeln("Logged in as " ~ mx.userId);

	mx.setDeviceName("rbot!");
	writeln(mx.getDeviceInfo(mx.deviceId).displayName);

	mx.setPresence(MatrixPresenceEnum.unavailable, "I am doing stuff!");
	writeln(mx.getPresence(mx.userId).presence);

	mx.sync();

	mx.messageDelegate = (&onMessage).toDelegate;
}

void onMessage(MatrixMessage m)
{
	if(MatrixTextMessage txt = cast(MatrixTextMessage)m)
	{
		
	}
}