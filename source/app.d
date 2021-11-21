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

	mx.setDeviceName("rbot!");
	writeln(mx.getDeviceInfo(mx.deviceId).displayName);

	mx.setPresence(MatrixPresenceEnum.unavailable, "I am doing stuff!");
	writeln(mx.getPresence(mx.userId).presence);

	JSONValue bigchungus = JSONValue();
	bigchungus["funny"] = 999_999;
	mx.setAccountData("rbot.bigchungus", bigchungus);
	writeln(mx.getAccountData("rbot.bigchungus"));

	JSONValue amongus = JSONValue();
	amongus["red"] = "sus";
	amongus["black"] = "vented";
	amongus["cyan"] = "dead";
	mx.setRoomData("#testing:ryhn.link", "rbot.amongus", amongus);
	writeln(mx.getRoomData("#testing:ryhn.link", "rbot.amongus"));

	// Oh? Aliases and room ids don't store the same data
	string id = mx.resolveRoomAlias("#testing:ryhn.link");
	writeln(id);
	mx.setRoomData(id, "rbot.amongus", amongus);
	writeln(mx.getRoomData(id, "rbot.amongus"));

	mx.sync();

	mx.messageDelegate = (&onMessage).toDelegate;
}

void onMessage(MatrixMessage m)
{
	if (MatrixTextMessage txt = cast(MatrixTextMessage) m)
	{

	}
}
