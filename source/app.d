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

	/*
	MatrixDeviceInfo[] devices = mx.getDevices();
	string[] deviceIds;
	foreach(d;devices)
	{
		if(d.deviceId == mx.deviceId) continue;

		writeln(d.deviceId);
		deviceIds ~= d.deviceId;
	}

	writeln();
	writeln("Deleting...");
	writeln();
	
	mx.deleteDevicesUsingPassword(deviceIds, password);

	devices = mx.getDevices();
	foreach(d;devices)
	{
		writeln(d.deviceId);
		deviceIds ~= d.deviceId;
	}
	*/

	mx.sync();
	mx.eventDelegate = (&onEvent).toDelegate;
	while(1)
	{
		mx.sync();
	}
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
